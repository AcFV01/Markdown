import Foundation

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
#endif

struct MarkdownSyntaxHighlighter {
    func apply(to storage: NSTextStorage, fontSize: CGFloat = 17) {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes(
            [
                .font: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: PlatformColor.markdownLabel
            ],
            range: fullRange
        )

        add(pattern: "(?ms)^```.*?^```[ \\t]*$", to: storage, attributes: [
            .foregroundColor: PlatformColor.systemOrange,
            .backgroundColor: PlatformColor.codeBackground
        ])
        add(pattern: "`[^`\\n]+`", to: storage, attributes: [
            .foregroundColor: PlatformColor.systemOrange,
            .backgroundColor: PlatformColor.codeBackground
        ])
        add(pattern: "(?m)^#{1,6}[ \\t]+.*$", to: storage, attributes: [
            .font: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: PlatformColor.systemPurple
        ])
        add(pattern: "(?m)^>[ \\t]?.*$", to: storage, attributes: [
            .foregroundColor: PlatformColor.markdownSecondaryLabel
        ])
        add(pattern: "(?m)^[ \\t]*(?:[-+*]|\\d+\\.|- \\[[ xX]\\])[ \\t]+", to: storage, attributes: [
            .foregroundColor: PlatformColor.systemBlue
        ])
        add(pattern: "\\[[^\\]]+\\]\\([^)]+\\)", to: storage, attributes: [
            .foregroundColor: PlatformColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        add(pattern: "(?:\\*\\*|__)(?=\\S)(.+?)(?<=\\S)(?:\\*\\*|__)", to: storage, attributes: [
            .font: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        ])
        add(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~", to: storage, attributes: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ])

        storage.endEditing()
    }

    private func add(
        pattern: String,
        to storage: NSTextStorage,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: storage.length)
        expression.enumerateMatches(in: storage.string, range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttributes(attributes, range: match.range)
        }
    }
}

private extension PlatformColor {
    static var markdownLabel: PlatformColor {
#if os(macOS)
        .labelColor
#else
        .label
#endif
    }

    static var markdownSecondaryLabel: PlatformColor {
#if os(macOS)
        .secondaryLabelColor
#else
        .secondaryLabel
#endif
    }

    static var codeBackground: PlatformColor {
        markdownSecondaryLabel.withAlphaComponent(0.12)
    }
}
