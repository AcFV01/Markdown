import Foundation

enum MarkdownFormattingAction: Equatable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case heading(Int)
    case quote
    case unorderedList
    case orderedList
    case taskList
    case codeBlock
    case wikiLink(String)
    case completeWikiLink(target: String, replacementRange: NSRange)
}

struct MarkdownFormattingRequest: Equatable {
    let id = UUID()
    let action: MarkdownFormattingAction
}

struct MarkdownTextMutation {
    let text: String
    let selection: NSRange

    static func apply(
        _ action: MarkdownFormattingAction,
        to text: String,
        selection: NSRange
    ) -> MarkdownTextMutation {
        switch action {
        case .bold:
            return wrap(text, selection: selection, prefix: "**", suffix: "**", placeholder: "bold text")
        case .italic:
            return wrap(text, selection: selection, prefix: "*", suffix: "*", placeholder: "italic text")
        case .strikethrough:
            return wrap(text, selection: selection, prefix: "~~", suffix: "~~", placeholder: "strikethrough")
        case .inlineCode:
            return wrap(text, selection: selection, prefix: "`", suffix: "`", placeholder: "code")
        case .link:
            return link(text, selection: selection)
        case let .heading(level):
            return heading(text, selection: selection, level: level)
        case .quote:
            return prefixLines(text, selection: selection, prefix: "> ")
        case .unorderedList:
            return prefixLines(text, selection: selection, prefix: "- ")
        case .orderedList:
            return prefixLines(text, selection: selection, prefix: "1. ")
        case .taskList:
            return prefixLines(text, selection: selection, prefix: "- [ ] ")
        case .codeBlock:
            return wrap(text, selection: selection, prefix: "```\n", suffix: "\n```", placeholder: "code")
        case let .wikiLink(target):
            return wikiLink(text, selection: selection, target: target)
        case let .completeWikiLink(target, replacementRange):
            return completeWikiLink(text, target: target, replacementRange: replacementRange)
        }
    }

    private static func wrap(
        _ text: String,
        selection: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> MarkdownTextMutation {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let selectedText = safeSelection.length == 0
            ? placeholder
            : source.substring(with: safeSelection)
        let replacement = prefix + selectedText + suffix
        let result = source.mutableCopy() as! NSMutableString
        result.replaceCharacters(in: safeSelection, with: replacement)

        let prefixLength = (prefix as NSString).length
        let selectedLength = (selectedText as NSString).length
        return MarkdownTextMutation(
            text: result as String,
            selection: NSRange(
                location: safeSelection.location + prefixLength,
                length: selectedLength
            )
        )
    }

    private static func link(_ text: String, selection: NSRange) -> MarkdownTextMutation {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let label = safeSelection.length == 0 ? "link text" : source.substring(with: safeSelection)
        let replacement = "[\(label)](https://)"
        let result = source.mutableCopy() as! NSMutableString
        result.replaceCharacters(in: safeSelection, with: replacement)

        return MarkdownTextMutation(
            text: result as String,
            selection: NSRange(
                location: safeSelection.location + ("[" as NSString).length,
                length: (label as NSString).length
            )
        )
    }

    private static func wikiLink(
        _ text: String,
        selection: NSRange,
        target: String
    ) -> MarkdownTextMutation {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let selectedText = safeSelection.length == 0
            ? nil
            : source.substring(with: safeSelection)
        let replacement = if let selectedText {
            "[[\(target)|\(selectedText)]]"
        } else {
            "[[\(target)]]"
        }
        let result = source.mutableCopy() as! NSMutableString
        result.replaceCharacters(in: safeSelection, with: replacement)
        return MarkdownTextMutation(
            text: result as String,
            selection: NSRange(
                location: safeSelection.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    private static func completeWikiLink(
        _ text: String,
        target: String,
        replacementRange: NSRange
    ) -> MarkdownTextMutation {
        let source = text as NSString
        let safeRange = clamped(replacementRange, to: source.length)
        let replacement = "[[\(target)]]"
        let result = source.mutableCopy() as! NSMutableString
        result.replaceCharacters(in: safeRange, with: replacement)
        return MarkdownTextMutation(
            text: result as String,
            selection: NSRange(
                location: safeRange.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    private static func heading(
        _ text: String,
        selection: NSRange,
        level: Int
    ) -> MarkdownTextMutation {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let lineRange = source.lineRange(for: safeSelection)
        let line = source.substring(with: lineRange)
        let content = line.replacingOccurrences(
            of: "^#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )
        let replacement = String(repeating: "#", count: min(max(level, 1), 6)) + " " + content
        let result = source.mutableCopy() as! NSMutableString
        result.replaceCharacters(in: lineRange, with: replacement)

        return MarkdownTextMutation(
            text: result as String,
            selection: NSRange(location: lineRange.location, length: (replacement as NSString).length)
        )
    }

    private static func prefixLines(
        _ text: String,
        selection: NSRange,
        prefix: String
    ) -> MarkdownTextMutation {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let lineRange = source.lineRange(for: safeSelection)
        let lines = source.substring(with: lineRange).components(separatedBy: "\n")
        let replacement = lines.enumerated().map { index, line in
            if line.isEmpty && index == lines.count - 1 {
                return line
            }
            return prefix + line
        }.joined(separator: "\n")

        let result = source.mutableCopy() as! NSMutableString
        result.replaceCharacters(in: lineRange, with: replacement)
        return MarkdownTextMutation(
            text: result as String,
            selection: NSRange(location: lineRange.location, length: (replacement as NSString).length)
        )
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let availableLength = length - location
        return NSRange(location: location, length: min(max(range.length, 0), availableLength))
    }
}

struct WikiLinkCompletionContext: Equatable {
    let query: String
    let noteTarget: String?
    let replacementRange: NSRange

    static func detect(in text: String, selection: NSRange) -> WikiLinkCompletionContext? {
        let source = text as NSString
        guard selection.length == 0,
              selection.location >= 2,
              selection.location <= source.length else { return nil }

        let searchRange = NSRange(location: 0, length: selection.location)
        let openingRange = source.range(of: "[[", options: .backwards, range: searchRange)
        guard openingRange.location != NSNotFound else { return nil }

        let queryLocation = NSMaxRange(openingRange)
        let queryRange = NSRange(
            location: queryLocation,
            length: selection.location - queryLocation
        )
        let fragment = source.substring(with: queryRange)
        let invalidCharacters = CharacterSet(charactersIn: "[]|\n\r")
        guard fragment.rangeOfCharacter(from: invalidCharacters) == nil else { return nil }

        let components = fragment.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let noteTarget: String?
        let query: String
        if components.count == 2 {
            let target = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return nil }
            noteTarget = target
            query = String(components[1])
        } else {
            noteTarget = nil
            query = fragment
        }

        return WikiLinkCompletionContext(
            query: query,
            noteTarget: noteTarget,
            replacementRange: NSRange(
                location: openingRange.location,
                length: selection.location - openingRange.location
            )
        )
    }
}
