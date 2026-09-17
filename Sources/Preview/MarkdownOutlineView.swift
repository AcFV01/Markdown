import SwiftUI

struct MarkdownOutlineView: View {
    let items: [MarkdownOutlineItem]
    let select: (MarkdownOutlineItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Add Markdown headings to build the outline.")
                )
            } else {
                List(items) { item in
                    Button {
                        select(item)
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
        .navigationTitle("Outline")
        .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 320)
    }
}
