import Combine
import Foundation

@MainActor
final class VaultAccessStore: ObservableObject {
    @Published private(set) var vaultURL: URL?
    @Published private(set) var errorMessage: String?

    private let bookmarkKey = "MarkdownEditor.VaultBookmark"
    private var isAccessingSecurityScopedResource = false

    init() {
        restoreBookmark()
    }

    var displayName: String {
        vaultURL?.lastPathComponent ?? "Current Folder"
    }

    func selectVault(_ url: URL) {
        stopCurrentAccess()
        let standardizedURL = url.standardizedFileURL
        isAccessingSecurityScopedResource = standardizedURL.startAccessingSecurityScopedResource()

        do {
            let bookmark = try standardizedURL.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            vaultURL = standardizedURL
            errorMessage = nil
        } catch {
            stopCurrentAccess()
            vaultURL = nil
            errorMessage = error.localizedDescription
        }
    }

    func useCurrentFolder() {
        stopCurrentAccess()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        vaultURL = nil
        errorMessage = nil
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
            vaultURL = url.standardizedFileURL
            errorMessage = nil
            if isStale {
                selectVault(url)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            vaultURL = nil
            errorMessage = error.localizedDescription
        }
    }

    private func stopCurrentAccess() {
        if isAccessingSecurityScopedResource, let vaultURL {
            vaultURL.stopAccessingSecurityScopedResource()
        }
        isAccessingSecurityScopedResource = false
    }

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
#if os(macOS)
        .withSecurityScope
#else
        .minimalBookmark
#endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
#if os(macOS)
        .withSecurityScope
#else
        []
#endif
    }
}
