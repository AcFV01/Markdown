import SwiftUI
import UniformTypeIdentifiers

enum EditorLayout: String, CaseIterable, Identifiable {
    case source
    case split
    case preview

    var id: Self { self }
}

struct MarkdownEditorView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var vaultAccess: VaultAccessStore
    @EnvironmentObject private var wikiNavigation: WikiNavigationStore
#if os(macOS)
    @Environment(\.openDocument) private var openDocument
#else
    @Environment(\.openURL) private var openURL
#endif
    @StateObject private var wikiLinkStore = WikiLinkStore()
    @State private var formattingRequest: MarkdownFormattingRequest?
    @State private var navigationRequest: MarkdownNavigationRequest?
    @State private var layout: EditorLayout = .split
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showingVaultImporter = false
    @State private var wikiLinkCompletion: WikiLinkCompletionContext?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MarkdownOutlineView(
                items: parsedDocument.outline,
                notes: wikiLinkStore.notes,
                outgoingLinks: wikiLinkStore.outgoingLinks,
                backlinks: wikiLinkStore.backlinks,
                localGraph: wikiLinkStore.localGraph,
                workspaceName: workspaceName,
                isIndexing: wikiLinkStore.isIndexing,
                errorMessage: wikiLinkStore.errorMessage ?? vaultAccess.errorMessage,
                selectHeading: { item in
                    navigationRequest = MarkdownNavigationRequest(
                        sourceLocation: item.sourceLocation
                    )
                },
                openDocument: { openLinkedDocument($0) },
                openWikiLink: openWikiTarget,
                createNote: createKnowledgeNote,
                refreshLinks: refreshLinkIndex
            )
        } detail: {
            VStack(spacing: 0) {
                EditorFormattingBar(
                    layout: $layout,
                    noteTargets: wikiLinkStore.noteLinkTargets
                ) { action in
                    formattingRequest = MarkdownFormattingRequest(action: action)
                }

                Divider()

                editorCanvas

                Divider()

                EditorStatusBar(
                    fileName: fileURL?.lastPathComponent ?? "Untitled.md",
                    statistics: TextStatistics(text: document.text)
                )
            }
            .background(Color.editorBackground)
            .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Choose Knowledge Base…") {
                        showingVaultImporter = true
                    }
                    if vaultAccess.vaultURL != nil {
                        Button("Use Current Document Folder") {
                            vaultAccess.useCurrentFolder()
                        }
                    }
                } label: {
                    Image(systemName: vaultAccess.vaultURL == nil ? "folder" : "folder.fill")
                }
                .help("Knowledge-base folder")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle outline")
            }
        }
        .fileImporter(
            isPresented: $showingVaultImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    vaultAccess.selectVault(url)
                }
            case .failure:
                break
            }
        }
        .task(id: linkIndexIdentity) {
            await wikiLinkStore.load(
                containing: fileURL,
                currentText: document.text,
                workspaceURL: effectiveWorkspaceURL
            )
            navigateToPendingHeadingIfNeeded()
        }
        .onChange(of: document.text) { _, newText in
            wikiLinkStore.updateCurrentDocument(url: fileURL, text: newText)
        }
        .onChange(of: wikiNavigation.pending?.id) { _, _ in
            navigateToPendingHeadingIfNeeded()
        }
        .onAppear {
            navigateToPendingHeadingIfNeeded()
        }
    }

    private var parsedDocument: MarkdownParseResult {
        MarkdownParser.parse(document.text)
    }

    private var linkIndexIdentity: String {
        [fileURL?.standardizedFileURL.path, effectiveWorkspaceURL?.standardizedFileURL.path]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private var workspaceName: String {
        if let vaultURL = vaultAccess.vaultURL {
            return "Knowledge Base: \(vaultURL.lastPathComponent)"
        }
        if let workspaceURL = wikiNavigation.workspace(for: fileURL) {
            return "Folder: \(workspaceURL.lastPathComponent)"
        }
        if let fileURL {
            return "Folder: \(fileURL.deletingLastPathComponent().lastPathComponent)"
        }
        return "No Knowledge Base"
    }

    private var effectiveWorkspaceURL: URL? {
        vaultAccess.vaultURL ?? wikiNavigation.workspace(for: fileURL)
    }

    @ViewBuilder
    private var editorCanvas: some View {
        switch layout {
        case .source:
            sourceEditor
        case .preview:
            MarkdownPreview(
                parsedDocument: parsedDocument,
                navigationRequest: navigationRequest,
                openWikiLink: openWikiTarget
            )
        case .split:
            if horizontalSizeClass == .compact {
                VStack(spacing: 0) {
                    sourceEditor
                    Divider()
                    MarkdownPreview(
                        parsedDocument: parsedDocument,
                        navigationRequest: navigationRequest,
                        openWikiLink: openWikiTarget
                    )
                }
            } else {
                HStack(spacing: 0) {
                    sourceEditor
                    Divider()
                    MarkdownPreview(
                        parsedDocument: parsedDocument,
                        navigationRequest: navigationRequest,
                        openWikiLink: openWikiTarget
                    )
                }
            }
        }
    }

    private var sourceEditor: some View {
        ZStack(alignment: .bottomLeading) {
            MarkdownTextEditor(
                text: $document.text,
                wikiLinkCompletion: $wikiLinkCompletion,
                formattingRequest: formattingRequest,
                navigationRequest: navigationRequest
            )
            .background(Color.editorBackground)
            .accessibilityLabel("Markdown editor")

            if let wikiLinkCompletion {
                WikiLinkCompletionPanel(
                    context: wikiLinkCompletion,
                    noteTargets: wikiLinkStore.noteLinkTargets,
                    headingTargets: headingSuggestions(for: wikiLinkCompletion),
                    selectTarget: completeWikiLink
                )
                .padding(12)
            }
        }
    }

    private func completeWikiLink(_ target: String) {
        guard let wikiLinkCompletion else { return }
        formattingRequest = MarkdownFormattingRequest(
            action: .completeWikiLink(
                target: target,
                replacementRange: wikiLinkCompletion.replacementRange
            )
        )
        self.wikiLinkCompletion = nil
    }

    private func openWikiTarget(_ link: WikiLinkDestination) {
        if let destination = wikiLinkStore.destination(for: link.target) {
            openLinkedDocument(destination, heading: link.heading)
            return
        }
        Task {
            do {
                let destination = try await wikiLinkStore.createNote(for: link.target)
                await wikiLinkStore.load(
                    containing: fileURL,
                    currentText: document.text,
                    workspaceURL: effectiveWorkspaceURL
                )
                openLinkedDocument(destination, heading: link.heading)
            } catch {
                wikiLinkStore.report(error)
            }
        }
    }

    private func createKnowledgeNote(_ name: String) {
        Task {
            do {
                let destination = try await wikiLinkStore.createNote(for: name)
                await wikiLinkStore.load(
                    containing: fileURL,
                    currentText: document.text,
                    workspaceURL: effectiveWorkspaceURL
                )
                openLinkedDocument(destination)
            } catch {
                wikiLinkStore.report(error)
            }
        }
    }

    private func openLinkedDocument(_ url: URL, heading: String? = nil) {
        if vaultAccess.vaultURL == nil, let workspaceURL = wikiLinkStore.workspaceURL {
            wikiNavigation.registerWorkspace(workspaceURL, for: url)
        }
        if let heading, !heading.isEmpty {
            wikiNavigation.request(destinationURL: url, heading: heading)
        }
#if os(macOS)
        Task {
            try? await openDocument(at: url)
        }
#else
        openURL(url)
#endif
    }

    private func headingSuggestions(for context: WikiLinkCompletionContext) -> [String] {
        guard let noteTarget = context.noteTarget else { return [] }
        return wikiLinkStore.headings(for: noteTarget)
    }

    private func navigateToPendingHeadingIfNeeded() {
        guard let navigation = wikiNavigation.navigation(for: fileURL) else { return }
        let expectedHeading = normalizedHeading(navigation.heading)
        if let item = parsedDocument.outline.first(where: {
            normalizedHeading($0.title) == expectedHeading
        }) {
            navigationRequest = MarkdownNavigationRequest(sourceLocation: item.sourceLocation)
        }
        wikiNavigation.consume(navigation)
    }

    private func normalizedHeading(_ heading: String) -> String {
        heading.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func refreshLinkIndex() {
        Task {
            await wikiLinkStore.load(
                containing: fileURL,
                currentText: document.text,
                workspaceURL: effectiveWorkspaceURL
            )
        }
    }
}

private struct EditorFormattingBar: View {
    @Binding var layout: EditorLayout
    let noteTargets: [String]
    let perform: (MarkdownFormattingAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                Menu {
                    ForEach(1...6, id: \.self) { level in
                        Button("Heading \(level)") {
                            perform(.heading(level))
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                }
                .help("Heading")

                Button {
                    perform(.bold)
                } label: {
                    Image(systemName: "bold")
                }
                .keyboardShortcut("b", modifiers: .command)
                .help("Bold (⌘B)")

                Button {
                    perform(.italic)
                } label: {
                    Image(systemName: "italic")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Italic (⌘I)")

                Button {
                    perform(.strikethrough)
                } label: {
                    Image(systemName: "strikethrough")
                }
                .help("Strikethrough")

                Button {
                    perform(.link)
                } label: {
                    Image(systemName: "link")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Link (⌘K)")

                Menu {
                    if noteTargets.isEmpty {
                        Text("No indexed notes")
                    } else {
                        ForEach(noteTargets, id: \.self) { target in
                            Button(target) {
                                perform(.wikiLink(target))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "link.badge.plus")
                }
                .help("Insert wiki link")

                Button {
                    perform(.inlineCode)
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .help("Inline code")

                Button {
                    perform(.quote)
                } label: {
                    Image(systemName: "text.quote")
                }
                .help("Quote")

                Menu {
                    Button("Bulleted List") { perform(.unorderedList) }
                    Button("Numbered List") { perform(.orderedList) }
                    Button("Task List") { perform(.taskList) }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .help("List")

                Button {
                    perform(.codeBlock)
                } label: {
                    Image(systemName: "curlybraces")
                }
                .help("Code block")
            }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 38)
            }
            .scrollIndicators(.hidden)

            Divider()
                .frame(height: 24)

            Picker("Layout", selection: $layout) {
                Image(systemName: "doc.plaintext")
                    .tag(EditorLayout.source)
                Image(systemName: "rectangle.split.2x1")
                    .tag(EditorLayout.split)
                Image(systemName: "eye")
                    .tag(EditorLayout.preview)
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .padding(.horizontal, 10)
        }
        .background(.bar)
    }
}

private struct WikiLinkCompletionPanel: View {
    let context: WikiLinkCompletionContext
    let noteTargets: [String]
    let headingTargets: [String]
    let selectTarget: (String) -> Void

    private var query: String {
        context.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [String] {
        let availableTargets = context.noteTarget == nil ? noteTargets : headingTargets
        let candidates = query.isEmpty
            ? availableTargets
            : availableTargets.filter { $0.localizedCaseInsensitiveContains(query) }
        return Array(candidates.prefix(6))
    }

    private var newTarget: String? {
        let availableTargets = context.noteTarget == nil ? noteTargets : headingTargets
        guard !query.isEmpty,
              !availableTargets.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) else {
            return nil
        }
        return completedTarget(query)
    }

    private var panelTitle: String {
        if let noteTarget = context.noteTarget {
            return "Heading in \(noteTarget)"
        }
        return "Link to note"
    }

    private var emptyMessage: String {
        if context.noteTarget != nil {
            return "No headings in this note"
        }
        return "Type a note name"
    }

    private func completedTarget(_ value: String) -> String {
        guard let noteTarget = context.noteTarget else { return value }
        return "\(noteTarget)#\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(panelTitle, systemImage: context.noteTarget == nil ? "link" : "number")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if matches.isEmpty && newTarget == nil {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(matches, id: \.self) { match in
                    completionButton(
                        title: context.noteTarget == nil ? match : "#\(match)",
                        systemImage: context.noteTarget == nil ? "doc.text" : "number",
                        target: completedTarget(match)
                    )
                }

                if let newTarget {
                    if !matches.isEmpty {
                        Divider()
                    }
                    completionButton(
                        title: context.noteTarget == nil
                            ? "Link to \(query)"
                            : "Link to #\(query)",
                        systemImage: "plus.circle",
                        target: newTarget
                    )
                }
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
        .shadow(radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wiki link suggestions")
    }

    private func completionButton(
        title: String,
        systemImage: String,
        target: String
    ) -> some View {
        Button {
            selectTarget(target)
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EditorStatusBar: View {
    let fileName: String
    let statistics: TextStatistics

    var body: some View {
        HStack(spacing: 16) {
            Text(fileName)
                .lineLimit(1)

            Spacer()

            Text("\(statistics.lines) lines")
            Text("\(statistics.words) words")
            Text("\(statistics.characters) characters")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

struct TextStatistics: Equatable {
    let characters: Int
    let words: Int
    let lines: Int

    init(text: String) {
        characters = text.count
        words = text.split { $0.isWhitespace || $0.isNewline }.count
        lines = text.isEmpty ? 0 : text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }
}

private extension Color {
    static var editorBackground: Color {
#if os(macOS)
        Color(nsColor: .textBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }
}

struct MarkdownEditorView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownEditorView(
            document: .constant(MarkdownDocument(text: "# Hello\n\nA Markdown document.")),
            fileURL: nil
        )
        .environmentObject(VaultAccessStore())
        .environmentObject(WikiNavigationStore())
    }
}
