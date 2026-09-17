import Foundation

struct MarkdownParseResult: Equatable {
    let blocks: [MarkdownBlockItem]
    let outline: [MarkdownOutlineItem]
}

struct MarkdownBlockItem: Identifiable, Equatable {
    let id: Int
    let block: MarkdownBlock
}

struct MarkdownOutlineItem: Identifiable, Equatable {
    var id: Int { sourceLocation }

    let level: Int
    let title: String
    let sourceLocation: Int
}

struct MarkdownTaskItem: Equatable {
    let isCompleted: Bool
    let text: String
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case unorderedList([String])
    case orderedList([String])
    case taskList([MarkdownTaskItem])
    case code(language: String?, content: String)
    case horizontalRule
}

enum MarkdownParser {
    static func parse(_ text: String) -> MarkdownParseResult {
        let lines = text.components(separatedBy: "\n")
        let offsets = sourceOffsets(for: lines)
        var blocks: [MarkdownBlockItem] = []
        var outline: [MarkdownOutlineItem] = []
        var paragraphLines: [String] = []
        var paragraphLocation = 0
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(
                MarkdownBlockItem(
                    id: paragraphLocation,
                    block: .paragraph(paragraphLines.joined(separator: "\n"))
                )
            )
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let location = offsets[index]

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let languageText = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(
                    MarkdownBlockItem(
                        id: location,
                        block: .code(
                            language: languageText.isEmpty ? nil : languageText,
                            content: codeLines.joined(separator: "\n")
                        )
                    )
                )
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(
                    MarkdownBlockItem(
                        id: location,
                        block: .heading(level: heading.level, text: heading.title)
                    )
                )
                outline.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: heading.title,
                        sourceLocation: location
                    )
                )
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlockItem(id: location, block: .horizontalRule))
                index += 1
                continue
            }

            if task(from: trimmed) != nil {
                flushParagraph()
                var items: [MarkdownTaskItem] = []
                while index < lines.count,
                      let item = task(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlockItem(id: location, block: .taskList(items)))
                continue
            }

            if unorderedItem(from: trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count,
                      let item = unorderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlockItem(id: location, block: .unorderedList(items)))
                continue
            }

            if orderedItem(from: trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count,
                      let item = orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(MarkdownBlockItem(id: location, block: .orderedList(items)))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(
                        String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces)
                    )
                    index += 1
                }
                blocks.append(
                    MarkdownBlockItem(
                        id: location,
                        block: .quote(quoteLines.joined(separator: "\n"))
                    )
                )
                continue
            }

            if paragraphLines.isEmpty {
                paragraphLocation = location
            }
            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return MarkdownParseResult(blocks: blocks, outline: outline)
    }

    private static func sourceOffsets(for lines: [String]) -> [Int] {
        var result: [Int] = []
        var offset = 0
        for line in lines {
            result.append(offset)
            offset += (line as NSString).length + 1
        }
        return result
    }

    private static func heading(from line: String) -> (level: Int, title: String)? {
        let prefix = line.prefix { $0 == "#" }
        guard (1...6).contains(prefix.count),
              line.dropFirst(prefix.count).first?.isWhitespace == true else { return nil }
        let title = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return (prefix.count, title)
    }

    private static func task(from line: String) -> MarkdownTaskItem? {
        let lowercased = line.lowercased()
        guard lowercased.hasPrefix("- [ ] ") || lowercased.hasPrefix("- [x] ") else { return nil }
        return MarkdownTaskItem(
            isCompleted: lowercased.hasPrefix("- [x] "),
            text: String(line.dropFirst(6))
        )
    }

    private static func unorderedItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> String? {
        guard let separator = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let number = line[..<separator]
        let remainderStart = line.index(after: separator)
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber),
              remainderStart < line.endIndex,
              line[remainderStart].isWhitespace else { return nil }
        return line[line.index(after: remainderStart)...].description
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else { return false }
        return ["-", "*", "_"].contains(marker) && compact.allSatisfy { $0 == marker }
    }
}
