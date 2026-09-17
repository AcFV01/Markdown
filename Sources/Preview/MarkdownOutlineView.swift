import SwiftUI

private enum SidebarSection: String, CaseIterable, Identifiable {
    case notes
    case outline
    case links
    case backlinks

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .outline: "Outline"
        case .links: "Links"
        case .backlinks: "Backlinks"
        }
    }
}

struct MarkdownOutlineView: View {
    let items: [MarkdownOutlineItem]
    let notes: [KnowledgeNote]
    let outgoingLinks: [ResolvedWikiLink]
    let backlinks: [MarkdownBacklink]
    let workspaceName: String
    let isIndexing: Bool
    let errorMessage: String?
    let selectHeading: (MarkdownOutlineItem) -> Void
    let openDocument: (URL) -> Void
    let openWikiLink: (WikiLinkDestination) -> Void
    let createNote: (String) -> Void
    let refreshLinks: () -> Void

    @State private var section: SidebarSection = .notes
    @State private var noteSearchText = ""
    @State private var newNoteName = ""
    @State private var isPresentingNewNote = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(workspaceName)
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack(spacing: 8) {
                Picker("Sidebar", selection: $section) {
                    ForEach(SidebarSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                if section == .notes {
                    Button {
                        presentNewNote()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .help("New note")
                }

                if section != .outline {
                    Button(action: refreshLinks) {
                        if isIndexing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isIndexing)
                    .help("Refresh links")
                }
            }
            .padding(10)

            Divider()

            if let errorMessage, section != .outline {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
            }

            switch section {
            case .notes:
                noteList
            case .outline:
                outlineList
            case .links:
                outgoingList
            case .backlinks:
                backlinkList
            }
        }
        .navigationTitle("Knowledge")
        .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 360)
        .alert("New Note", isPresented: $isPresentingNewNote) {
            TextField("Name or folder/name", text: $newNoteName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                submitNewNote()
            }
            .disabled(trimmedNewNoteName.isEmpty)
        } message: {
            Text("Create a Markdown note in the current knowledge base.")
        }
    }

    @ViewBuilder
    private var noteList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $noteSearchText)
                    .textFieldStyle(.plain)
                if !noteSearchText.isEmpty {
                    Button {
                        noteSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if filteredNotes.isEmpty && !trimmedSearchText.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No notes contain \"\(trimmedSearchText)\".")
                } actions: {
                    Button("Create \"\(trimmedSearchText)\"") {
                        createNote(trimmedSearchText)
                        noteSearchText = ""
                    }
                }
            } else if notes.isEmpty {
                ContentUnavailableView {
                    Label("No Notes", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Markdown files in this folder will appear here.")
                } actions: {
                    Button("Create Note") {
                        presentNewNote()
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredNotes) { note in
                            Button {
                                openDocument(note.url)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(note.title)
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        if note.relativePath != note.title {
                                            Text(note.relativePath)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text(note.excerpt)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var filteredNotes: [KnowledgeNote] {
        guard !trimmedSearchText.isEmpty else { return notes }
        return notes.filter { note in
            note.searchableText.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var trimmedSearchText: String {
        noteSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewNoteName: String {
        newNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentNewNote(defaultName: String = "") {
        newNoteName = defaultName
        isPresentingNewNote = true
    }

    private func submitNewNote() {
        guard !trimmedNewNoteName.isEmpty else { return }
        createNote(trimmedNewNoteName)
        noteSearchText = ""
        newNoteName = ""
    }

    @ViewBuilder
    private var outlineList: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Headings",
                systemImage: "list.bullet.indent",
                description: Text("Add Markdown headings to build the outline.")
            )
        } else {
            List(items) { item in
                Button {
                    selectHeading(item)
                } label: {
                    HStack(spacing: 8) {
                        Text("H\(item.level)")
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(item.title)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                    .padding(.leading, CGFloat(max(0, item.level - 1)) * 10)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var outgoingList: some View {
        if outgoingLinks.isEmpty {
            ContentUnavailableView(
                "No Links",
                systemImage: "link",
                description: Text("Use [[Note]] to link to another Markdown file.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(outgoingLinks) { resolvedLink in
                        Button {
                            openWikiLink(
                                WikiLinkDestination(
                                    target: resolvedLink.link.target,
                                    heading: resolvedLink.link.heading
                                )
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: resolvedLink.destinationURL == nil ? "questionmark.circle" : "link")
                                    .foregroundStyle(resolvedLink.destinationURL == nil ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(resolvedLink.link.displayText)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text(resolvedLink.destinationURL == nil ? "Create note" : "Linked note")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backlinkList: some View {
        if backlinks.isEmpty {
            ContentUnavailableView(
                "No Backlinks",
                systemImage: "arrowshape.turn.up.backward",
                description: Text("Notes that link here will appear in this list.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(backlinks) { backlink in
                        Button {
                            openDocument(backlink.sourceURL)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(backlink.sourceTitle, systemImage: "doc.text")
                                    .foregroundStyle(.primary)
                                Text(backlink.excerpt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}
