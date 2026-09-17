import Combine
import Foundation

@MainActor
final class WikiLinkStore: ObservableObject {
    @Published private(set) var outgoingLinks: [ResolvedWikiLink] = []
    @Published private(set) var backlinks: [MarkdownBacklink] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var errorMessage: String?

    private var index = WorkspaceLinkIndex(notes: [])
    private var currentURL: URL?

    func load(containing fileURL: URL?, currentText: String) async {
        guard let fileURL else {
            clear()
            return
        }

        isIndexing = true
        errorMessage = nil
        do {
            let result = try await WorkspaceLinkIndex.build(
                containing: fileURL,
                currentText: currentText
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

    private func publishSnapshot() {
        guard let currentURL else {
            outgoingLinks = []
            backlinks = []
            return
        }
        outgoingLinks = index.outgoingLinks(from: currentURL)
        backlinks = index.backlinks(to: currentURL)
    }

    private func clear() {
        index = WorkspaceLinkIndex(notes: [])
        currentURL = nil
        outgoingLinks = []
        backlinks = []
        isIndexing = false
        errorMessage = nil
    }
}
