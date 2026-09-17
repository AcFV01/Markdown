import Foundation

struct ResolvedWikiLink: Identifiable, Equatable, Sendable {
    var id: String { link.id }

    let link: WikiLink
    let destinationURL: URL?
}

struct MarkdownBacklink: Identifiable, Equatable, Sendable {
    var id: String { "\(sourceURL.path):\(sourceRange.location)" }

    let sourceURL: URL
    let sourceTitle: String
    let excerpt: String
    let sourceRange: NSRange
}

struct IndexedMarkdownNote: Equatable, Sendable {
    let url: URL
    let title: String
    let relativePathKey: String
    let titleKey: String
    let content: String
    let links: [WikiLink]
}

struct WorkspaceLinkIndex: Sendable {
    private(set) var notes: [IndexedMarkdownNote]
    let rootDirectory: URL?
    private let destinations: [String: URL]

    init(notes: [IndexedMarkdownNote], rootDirectory: URL? = nil) {
        self.notes = notes.sorted { $0.url.path < $1.url.path }
        self.rootDirectory = rootDirectory
        var destinations: [String: URL] = [:]
        for note in self.notes {
            destinations[note.relativePathKey] = destinations[note.relativePathKey] ?? note.url
            destinations[note.titleKey] = destinations[note.titleKey] ?? note.url
        }
        self.destinations = destinations
    }

    var noteTitles: [String] {
        Array(Set(notes.map(\.title))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func build(
        containing currentURL: URL,
        currentText: String,
        workspaceURL: URL? = nil
    ) async throws -> WorkspaceLinkIndex {
        try await Task.detached(priority: .utility) {
            try scanDirectory(
                containing: currentURL,
                currentText: currentText,
                workspaceURL: workspaceURL
            )
        }.value
    }

    private static func scanDirectory(
        containing currentURL: URL,
        currentText: String,
        workspaceURL: URL?
    ) throws -> WorkspaceLinkIndex {
        let directory = workspaceURL?.standardizedFileURL
            ?? currentURL.deletingLastPathComponent()
        let didAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let currentPath = currentURL.standardizedFileURL.path
        var notes: [IndexedMarkdownNote] = []
        for case let url as URL in enumerator {
            if Task<Never, Never>.isCancelled {
                throw CancellationError()
            }
            guard isMarkdownFile(url) else { continue }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true,
                  (values?.fileSize ?? 0) <= 5_000_000 else { continue }

            let content: String
            if url.standardizedFileURL.path == currentPath {
                content = currentText
            } else if let data = try? Data(contentsOf: url) {
                content = String(decoding: data, as: UTF8.self)
            } else {
                continue
            }

            notes.append(makeNote(url: url, content: content, relativeTo: directory))
        }

        if !notes.contains(where: { $0.url.standardizedFileURL.path == currentPath }) {
            notes.append(makeNote(url: currentURL, content: currentText, relativeTo: directory))
        }
        return WorkspaceLinkIndex(notes: notes, rootDirectory: directory)
    }

    func updatingNote(at url: URL, content: String) -> WorkspaceLinkIndex {
        let path = url.standardizedFileURL.path
        let directory = rootDirectory ?? url.deletingLastPathComponent()
        var updated = notes.filter { $0.url.standardizedFileURL.path != path }
        updated.append(Self.makeNote(url: url, content: content, relativeTo: directory))
        return WorkspaceLinkIndex(notes: updated, rootDirectory: directory)
    }

    func outgoingLinks(from url: URL) -> [ResolvedWikiLink] {
        guard let note = note(at: url) else { return [] }
        return note.links.map { link in
            ResolvedWikiLink(link: link, destinationURL: destination(for: link.target))
        }
    }

    func backlinks(to url: URL) -> [MarkdownBacklink] {
        let targetPath = url.standardizedFileURL.path
        return notes.flatMap { note in
            note.links.compactMap { link in
                guard destination(for: link.target)?.standardizedFileURL.path == targetPath else {
                    return nil
                }
                return MarkdownBacklink(
                    sourceURL: note.url,
                    sourceTitle: note.title,
                    excerpt: excerpt(containing: link, in: note.content),
                    sourceRange: link.range
                )
            }
        }
        .sorted {
            if $0.sourceTitle == $1.sourceTitle {
                return $0.sourceRange.location < $1.sourceRange.location
            }
            return $0.sourceTitle.localizedStandardCompare($1.sourceTitle) == .orderedAscending
        }
    }

    func destination(for target: String) -> URL? {
        let key = WikiLinkParser.normalizedTarget(target)
        if let exact = destinations[key] {
            return exact
        }
        let titleKey = WikiLinkParser.normalizedTarget(
            URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
        )
        return destinations[titleKey]
    }

    private func note(at url: URL) -> IndexedMarkdownNote? {
        let path = url.standardizedFileURL.path
        return notes.first { $0.url.standardizedFileURL.path == path }
    }

    private func excerpt(containing link: WikiLink, in content: String) -> String {
        let source = content as NSString
        let safeLocation = min(link.range.location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: safeLocation, length: 0))
        return source.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeNote(
        url: URL,
        content: String,
        relativeTo directory: URL
    ) -> IndexedMarkdownNote {
        let title = url.deletingPathExtension().lastPathComponent
        let directoryPath = directory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        var relativePath = filePath.hasPrefix(directoryPath)
            ? String(filePath.dropFirst(directoryPath.count))
            : title
        while relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        relativePath = (relativePath as NSString).deletingPathExtension

        return IndexedMarkdownNote(
            url: url,
            title: title,
            relativePathKey: WikiLinkParser.normalizedTarget(relativePath),
            titleKey: WikiLinkParser.normalizedTarget(title),
            content: content,
            links: WikiLinkParser.links(in: content)
        )
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased())
    }
}
