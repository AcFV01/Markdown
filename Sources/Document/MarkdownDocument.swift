import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdownDocument, .plainText]
    }

    static var writableContentTypes: [UTType] {
        [.markdownDocument]
    }

    var text: String

    init(text: String = "# Untitled\n\nStart writing…\n") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private extension UTType {
    static let markdownDocument = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}
