import SwiftUI

struct MarkdownNavigationRequest: Equatable {
    let id = UUID()
    let sourceLocation: Int
}

struct MarkdownPreview: View {
    let parsedDocument: MarkdownParseResult
    let navigationRequest: MarkdownNavigationRequest?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(parsedDocument.blocks) { item in
                        blockView(item.block)
                            .id(item.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.previewBackground)
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let navigationRequest else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(navigationRequest.sourceLocation, anchor: .top)
                }
            }
        }
        .accessibilityLabel("Markdown preview")
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .fontWeight(.bold)
                .textSelection(.enabled)

        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)

        case let .quote(text):
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: 4)
                Text(inlineMarkdown(text))
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
            }

        case let .unorderedList(items):
            list(items: items, ordered: false)

        case let .orderedList(items):
            list(items: items, ordered: true)

        case let .taskList(items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                        Text(inlineMarkdown(item.text))
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    }
                }
            }

        case let .code(language, content):
            VStack(alignment: .leading, spacing: 8) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codeBackground, in: RoundedRectangle(cornerRadius: 8))

        case .horizontalRule:
            Divider()
        }
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(inlineMarkdown(item))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .largeTitle
        case 2: .title
        case 3: .title2
        case 4: .title3
        default: .headline
        }
    }
}

private extension Color {
    static var previewBackground: Color {
#if os(macOS)
        Color(nsColor: .textBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }

    static var codeBackground: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }
}
