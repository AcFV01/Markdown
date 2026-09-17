import SwiftUI

private enum SidebarSection: String, CaseIterable, Identifiable {
    case outline
    case links
    case backlinks

    var id: Self { self }

    var title: String {
        switch self {
        case .outline: "Outline"
        case .links: "Links"
        case .backlinks: "Backlinks"
        }
    }
}

struct MarkdownOutlineView: View {
    let items: [MarkdownOutlineItem]
    let outgoingLinks: [ResolvedWikiLink]
    let backlinks: [MarkdownBacklink]
    let isIndexing: Bool
    let errorMessage: String?
    let selectHeading: (MarkdownOutlineItem) -> Void
    let openDocument: (URL) -> Void
    let refreshLinks: () -> Void

    @State private var section: SidebarSection = .outline

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Sidebar", selection: $section) {
                    ForEach(SidebarSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

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
                            guard let destination = resolvedLink.destinationURL else { return }
                            openDocument(destination)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: resolvedLink.destinationURL == nil ? "questionmark.circle" : "link")
                                    .foregroundStyle(resolvedLink.destinationURL == nil ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(resolvedLink.link.displayText)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text(resolvedLink.destinationURL == nil ? "Unresolved" : "Linked note")
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
                        .disabled(resolvedLink.destinationURL == nil)
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
