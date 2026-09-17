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

struct KnowledgeNote: Identifiable, Equatable, Sendable {
    var id: String { url.standardizedFileURL.path }

    let url: URL
    let title: String
    let relativePath: String
    let excerpt: String
    let searchableText: String
}

struct KnowledgeGraphNode: Identifiable, Equatable, Sendable {
    var id: String { url.standardizedFileURL.path }

    let url: URL
    let title: String
    let relativePath: String
}

struct KnowledgeGraphEdge: Identifiable, Equatable, Sendable {
    var id: String { "\(sourceID)->\(destinationID)" }

    let sourceID: String
    let destinationID: String
}

struct KnowledgeGraphSnapshot: Equatable, Sendable {
    let currentNodeID: String?
    let nodes: [KnowledgeGraphNode]
    let edges: [KnowledgeGraphEdge]

    static let empty = KnowledgeGraphSnapshot(
        currentNodeID: nil,
        nodes: [],
        edges: []
    )
}

struct IndexedMarkdownNote: Equatable, Sendable {
    let url: URL
    let title: String
    let relativePath: String
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

    var noteLinkTargets: [String] {
        Array(Set(notes.map(\.relativePath))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var knowledgeNotes: [KnowledgeNote] {
        notes.map { note in
            KnowledgeNote(
                url: note.url,
                title: note.title,
                relativePath: note.relativePath,
                excerpt: Self.noteExcerpt(from: note.content),
                searchableText: "\(note.relativePath)\n\(note.content)"
            )
        }
        .sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
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

    func localGraph(around url: URL) -> KnowledgeGraphSnapshot {
        guard let currentNote = note(at: url) else { return .empty }
        let currentID = currentNote.url.standardizedFileURL.path
        var nodesByID: [String: KnowledgeGraphNode] = [
            currentID: Self.graphNode(from: currentNote)
        ]
        var edgesByID: [String: KnowledgeGraphEdge] = [:]

        func addEdge(from source: IndexedMarkdownNote, to destination: IndexedMarkdownNote) {
            let sourceID = source.url.standardizedFileURL.path
            let destinationID = destination.url.standardizedFileURL.path
            guard sourceID != destinationID else { return }
            nodesByID[sourceID] = Self.graphNode(from: source)
            nodesByID[destinationID] = Self.graphNode(from: destination)
            let edge = KnowledgeGraphEdge(
                sourceID: sourceID,
                destinationID: destinationID
            )
            edgesByID[edge.id] = edge
        }

        for link in currentNote.links {
            guard let destinationURL = destination(for: link.target),
                  let destinationNote = note(at: destinationURL) else { continue }
            addEdge(from: currentNote, to: destinationNote)
        }

        for sourceNote in notes where sourceNote.url.standardizedFileURL.path != currentID {
            for link in sourceNote.links {
                guard destination(for: link.target)?.standardizedFileURL.path == currentID else {
                    continue
                }
                addEdge(from: sourceNote, to: currentNote)
            }
        }

        let nodes = nodesByID.values.sorted { lhs, rhs in
            if lhs.id == currentID { return true }
            if rhs.id == currentID { return false }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        let edges = edgesByID.values.sorted { $0.id < $1.id }
        return KnowledgeGraphSnapshot(
            currentNodeID: currentID,
            nodes: nodes,
            edges: edges
        )
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

    func headings(for target: String) -> [String] {
        guard let destination = destination(for: target),
              let note = note(at: destination) else { return [] }
        var seen: Set<String> = []
        return Self.headings(in: note.content).filter { heading in
            seen.insert(heading).inserted
        }
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
            relativePath: relativePath,
            relativePathKey: WikiLinkParser.normalizedTarget(relativePath),
            titleKey: WikiLinkParser.normalizedTarget(title),
            content: content,
            links: WikiLinkParser.links(in: content)
        )
    }

    private static func graphNode(from note: IndexedMarkdownNote) -> KnowledgeGraphNode {
        KnowledgeGraphNode(
            url: note.url,
            title: note.title,
            relativePath: note.relativePath
        )
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased())
    }

    private static func headings(in content: String) -> [String] {
        content.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prefix = trimmed.prefix { $0 == "#" }
            guard (1...6).contains(prefix.count),
                  trimmed.dropFirst(prefix.count).first?.isWhitespace == true else {
                return nil
            }
            let title = trimmed.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
    }

    private static func noteExcerpt(from content: String) -> String {
        let lines = content
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let bodyLine = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") }) {
            return bodyLine
        }
        return lines
            .first(where: { !$0.isEmpty })?
            .replacingOccurrences(
                of: #"^#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
            ?? "Empty note"
    }
}
