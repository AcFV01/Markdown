import SwiftUI

@main
struct MarkdownEditorApp: App {
    @StateObject private var vaultAccess = VaultAccessStore()
    @StateObject private var wikiNavigation = WikiNavigationStore()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            MarkdownEditorView(
                document: configuration.$document,
                fileURL: configuration.fileURL
            )
            .environmentObject(vaultAccess)
            .environmentObject(wikiNavigation)
        }
    }
}
