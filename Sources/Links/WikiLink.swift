import Foundation

struct WikiLink: Identifiable, Equatable, Sendable {
    var id: String { "\(range.location):\(rawValue)" }

    let rawValue: String
    let target: String
    let heading: String?
    let alias: String?
    let range: NSRange

    var displayText: String {
        if let alias, !alias.isEmpty {
            return alias
        }
        if let heading, !heading.isEmpty {
            return "\(target) › \(heading)"
        }
        return target
    }
}

enum WikiLinkParser {
    private static let pattern = #"\[\[([^\]|#]+?)(?:#([^\]|]+?))?(?:\|([^\]]+?))?\]\]"#

    static func links(in text: String) -> [WikiLink] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        let searchRange = NSRange(location: 0, length: source.length)

        return expression.matches(in: text, range: searchRange).compactMap { match in
            guard let target = capture(1, from: match, source: source) else { return nil }
            return WikiLink(
                rawValue: source.substring(with: match.range),
                target: target.trimmingCharacters(in: .whitespacesAndNewlines),
                heading: capture(2, from: match, source: source)?.trimmingCharacters(in: .whitespacesAndNewlines),
                alias: capture(3, from: match, source: source)?.trimmingCharacters(in: .whitespacesAndNewlines),
                range: match.range
            )
        }
    }

    static func markdownCompatibleText(_ text: String) -> String {
        let links = links(in: text)
        guard !links.isEmpty else { return text }

        let result = (text as NSString).mutableCopy() as! NSMutableString
        for link in links.reversed() {
            var components = URLComponents()
            components.scheme = "markdown-editor"
            components.host = "wiki"
            components.queryItems = [
                URLQueryItem(name: "target", value: link.target),
                URLQueryItem(name: "heading", value: link.heading)
            ].filter { $0.value != nil }

            guard let destination = components.string else { continue }
            let label = link.displayText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "]", with: "\\]")
            result.replaceCharacters(
                in: link.range,
                with: "[\(label)](\(destination))"
            )
        }
        return result as String
    }

    static func target(from url: URL) -> String? {
        guard url.scheme == "markdown-editor", url.host == "wiki" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "target" })?
            .value
    }

    static func normalizedTarget(_ target: String) -> String {
        var normalized = target
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if normalized.lowercased().hasSuffix(".md") {
            normalized.removeLast(3)
        } else if normalized.lowercased().hasSuffix(".markdown") {
            normalized.removeLast(9)
        } else if normalized.lowercased().hasSuffix(".mdown") {
            normalized.removeLast(6)
        }
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        return normalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }

    private static func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        source: NSString
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range)
    }
}
