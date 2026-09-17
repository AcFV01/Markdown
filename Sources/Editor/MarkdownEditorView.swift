import SwiftUI

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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MarkdownOutlineView(
                items: parsedDocument.outline,
                outgoingLinks: wikiLinkStore.outgoingLinks,
                backlinks: wikiLinkStore.backlinks,
                isIndexing: wikiLinkStore.isIndexing,
                errorMessage: wikiLinkStore.errorMessage,
                selectHeading: { item in
                    navigationRequest = MarkdownNavigationRequest(
                        sourceLocation: item.sourceLocation
                    )
                },
                openDocument: openLinkedDocument,
                refreshLinks: refreshLinkIndex
            )
        } detail: {
            VStack(spacing: 0) {
                EditorFormattingBar(layout: $layout) { action in
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
                Button {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle outline")
            }
        }
        .task(id: fileURL) {
            await wikiLinkStore.load(
                containing: fileURL,
                currentText: document.text
            )
        }
        .onChange(of: document.text) { _, newText in
            wikiLinkStore.updateCurrentDocument(url: fileURL, text: newText)
        }
    }

    private var parsedDocument: MarkdownParseResult {
        MarkdownParser.parse(document.text)
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
        MarkdownTextEditor(
            text: $document.text,
            formattingRequest: formattingRequest,
            navigationRequest: navigationRequest
        )
        .background(Color.editorBackground)
        .accessibilityLabel("Markdown editor")
    }

    private func openWikiTarget(_ target: String) {
        guard let destination = wikiLinkStore.destination(for: target) else { return }
        openLinkedDocument(destination)
    }

    private func openLinkedDocument(_ url: URL) {
#if os(macOS)
        Task {
            try? await openDocument(at: url)
        }
#else
        openURL(url)
#endif
    }

    private func refreshLinkIndex() {
        Task {
            await wikiLinkStore.load(
                containing: fileURL,
                currentText: document.text
            )
        }
    }
}

private struct EditorFormattingBar: View {
    @Binding var layout: EditorLayout
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
    }
}
