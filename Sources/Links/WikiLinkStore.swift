import Combine
import Foundation

@MainActor
final class WikiLinkStore: ObservableObject {
    @Published private(set) var outgoingLinks: [ResolvedWikiLink] = []
    @Published private(set) var backlinks: [MarkdownBacklink] = []
    @Published private(set) var noteTitles: [String] = []
    @Published private(set) var noteLinkTargets: [String] = []
    @Published private(set) var notes: [KnowledgeNote] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var errorMessage: String?

    private var index = WorkspaceLinkIndex(notes: [])
    private var currentURL: URL?

    func load(
        containing fileURL: URL?,
        currentText: String,
        workspaceURL: URL? = nil
    ) async {
        guard let fileURL else {
            clear()
            return
        }

        isIndexing = true
        errorMessage = nil
        do {
            let result = try await WorkspaceLinkIndex.build(
                containing: fileURL,
                currentText: currentText,
                workspaceURL: workspaceURL
            )
            try Task.checkCancellation()
            index = result
            currentURL = fileURL
            publishSnapshot()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isIndexing = false
    }

    func updateCurrentDocument(url: URL?, text: String) {
        guard let url else { return }
        if currentURL?.standardizedFileURL.path != url.standardizedFileURL.path {
            currentURL = url
        }
        index = index.updatingNote(at: url, content: text)
        publishSnapshot()
    }

    func destination(for target: String) -> URL? {
        index.destination(for: target)
    }

    func headings(for target: String) -> [String] {
        index.headings(for: target)
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func createNote(for target: String) async throws -> URL {
        if let existing = destination(for: target) {
            return existing
        }
        guard let rootDirectory = index.rootDirectory else {
            throw WikiLinkCreationError.noWorkspace
        }
        return try await WikiLinkFileCreator.createNote(
            target: target,
            in: rootDirectory
        )
    }

    private func publishSnapshot() {
        guard let currentURL else {
            outgoingLinks = []
            backlinks = []
            return
        }
        outgoingLinks = index.outgoingLinks(from: currentURL)
        backlinks = index.backlinks(to: currentURL)
        noteTitles = index.noteTitles
        noteLinkTargets = index.noteLinkTargets
        notes = index.knowledgeNotes
    }

    private func clear() {
        index = WorkspaceLinkIndex(notes: [])
        currentURL = nil
        outgoingLinks = []
        backlinks = []
        noteTitles = []
        noteLinkTargets = []
        notes = []
        isIndexing = false
        errorMessage = nil
    }
}

struct PendingWikiNavigation: Identifiable, Equatable {
    let id = UUID()
    let destinationURL: URL
    let heading: String
}

@MainActor
final class WikiNavigationStore: ObservableObject {
    @Published private(set) var pending: PendingWikiNavigation?

    func request(destinationURL: URL, heading: String) {
        pending = PendingWikiNavigation(
            destinationURL: destinationURL.standardizedFileURL,
            heading: heading
        )
    }

    func navigation(for fileURL: URL?) -> PendingWikiNavigation? {
        guard let fileURL, let pending,
              fileURL.standardizedFileURL.path == pending.destinationURL.path else {
            return nil
        }
        return pending
    }

    func consume(_ navigation: PendingWikiNavigation) {
        guard pending?.id == navigation.id else { return }
        pending = nil
    }
}

private enum WikiLinkCreationError: LocalizedError {
    case noWorkspace
    case invalidTarget

    var errorDescription: String? {
        switch self {
        case .noWorkspace:
            "Choose a knowledge-base folder before creating linked notes."
        case .invalidTarget:
            "The linked note name is not valid."
        }
    }
}

private enum WikiLinkFileCreator {
    static func createNote(target: String, in rootDirectory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            var path = target
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
            guard !path.hasPrefix("/") else {
                throw WikiLinkCreationError.invalidTarget
            }
            path = (path as NSString).deletingPathExtension
            let components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw WikiLinkCreationError.invalidTarget
            }

            let root = rootDirectory.standardizedFileURL
            let didAccess = root.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            var destinationDirectory = root
            for component in components.dropLast() {
                destinationDirectory.appendPathComponent(component, isDirectory: true)
            }
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )

            let title = components.last ?? "Untitled"
            let destination = destinationDirectory
                .appendingPathComponent(title)
                .appendingPathExtension("md")
                .standardizedFileURL
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard destination.path.hasPrefix(rootPrefix) else {
                throw WikiLinkCreationError.invalidTarget
            }

            if !FileManager.default.fileExists(atPath: destination.path) {
                try Data("# \(title)\n\n".utf8).write(to: destination, options: .atomic)
            }
            return destination
        }.value
    }
}
