import SwiftUI

#if os(macOS)
import AppKit

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var wikiLinkCompletion: WikiLinkCompletionContext?
    let formattingRequest: MarkdownFormattingRequest?
    let navigationRequest: MarkdownNavigationRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        context.coordinator.highlight(textView)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.synchronize(textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        private var isSynchronizing = false
        private var lastRequestID: UUID?
        private var lastNavigationID: UUID?
        private let highlighter = MarkdownSyntaxHighlighter()

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isSynchronizing,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView)
            publishCompletion(from: textView.string, selection: textView.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isSynchronizing,
                  let textView = notification.object as? NSTextView else { return }
            publishCompletion(from: textView.string, selection: textView.selectedRange())
        }

        func synchronize(_ textView: NSTextView) {
            if textView.string != parent.text {
                isSynchronizing = true
                let selection = textView.selectedRange()
                textView.string = parent.text
                textView.setSelectedRange(clamp(selection, to: (parent.text as NSString).length))
                highlight(textView)
                isSynchronizing = false
            }

            guard let request = parent.formattingRequest,
                  request.id != lastRequestID else {
                navigate(textView)
                return
            }
            apply(request, to: textView)
            navigate(textView)
        }

        private func apply(_ request: MarkdownFormattingRequest, to textView: NSTextView) {
            lastRequestID = request.id
            let mutation = MarkdownTextMutation.apply(
                request.action,
                to: textView.string,
                selection: textView.selectedRange()
            )
            isSynchronizing = true
            textView.string = mutation.text
            textView.setSelectedRange(mutation.selection)
            parent.text = mutation.text
            highlight(textView)
            isSynchronizing = false
            textView.window?.makeFirstResponder(textView)
        }

        private func navigate(_ textView: NSTextView) {
            guard let request = parent.navigationRequest,
                  request.id != lastNavigationID else { return }
            lastNavigationID = request.id
            let location = min(request.sourceLocation, textView.string.utf16.count)
            let range = NSRange(location: location, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        private func publishCompletion(from text: String, selection: NSRange) {
            let completion = WikiLinkCompletionContext.detect(in: text, selection: selection)
            if parent.wikiLinkCompletion != completion {
                parent.wikiLinkCompletion = completion
            }
        }

        func highlight(_ textView: NSTextView) {
            let selection = textView.selectedRange()
            highlighter.apply(to: textView.textStorage ?? NSTextStorage())
            textView.setSelectedRange(clamp(selection, to: textView.string.utf16.count))
        }

        private func clamp(_ range: NSRange, to length: Int) -> NSRange {
            let location = min(range.location, length)
            return NSRange(location: location, length: min(range.length, length - location))
        }
    }
}

#else
import UIKit

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var wikiLinkCompletion: WikiLinkCompletionContext?
    let formattingRequest: MarkdownFormattingRequest?
    let navigationRequest: MarkdownNavigationRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.autocorrectionType = .yes
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        textView.text = text
        context.coordinator.highlight(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(textView)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextEditor
        private var isSynchronizing = false
        private var lastRequestID: UUID?
        private var lastNavigationID: UUID?
        private let highlighter = MarkdownSyntaxHighlighter()

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isSynchronizing else { return }
            parent.text = textView.text
            highlight(textView)
            publishCompletion(from: textView.text, selection: textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isSynchronizing else { return }
            publishCompletion(from: textView.text, selection: textView.selectedRange)
        }

        func synchronize(_ textView: UITextView) {
            if textView.text != parent.text {
                isSynchronizing = true
                let selection = textView.selectedRange
                textView.text = parent.text
                textView.selectedRange = clamp(selection, to: (parent.text as NSString).length)
                highlight(textView)
                isSynchronizing = false
            }

            guard let request = parent.formattingRequest,
                  request.id != lastRequestID else {
                navigate(textView)
                return
            }
            apply(request, to: textView)
            navigate(textView)
        }

        private func apply(_ request: MarkdownFormattingRequest, to textView: UITextView) {
            lastRequestID = request.id
            let mutation = MarkdownTextMutation.apply(
                request.action,
                to: textView.text,
                selection: textView.selectedRange
            )
            isSynchronizing = true
            textView.text = mutation.text
            textView.selectedRange = mutation.selection
            parent.text = mutation.text
            highlight(textView)
            isSynchronizing = false
            textView.becomeFirstResponder()
        }

        private func navigate(_ textView: UITextView) {
            guard let request = parent.navigationRequest,
                  request.id != lastNavigationID else { return }
            lastNavigationID = request.id
            let location = min(request.sourceLocation, textView.text.utf16.count)
            let range = NSRange(location: location, length: 0)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }

        private func publishCompletion(from text: String, selection: NSRange) {
            let completion = WikiLinkCompletionContext.detect(in: text, selection: selection)
            if parent.wikiLinkCompletion != completion {
                parent.wikiLinkCompletion = completion
            }
        }

        func highlight(_ textView: UITextView) {
            let selection = textView.selectedRange
            highlighter.apply(to: textView.textStorage)
            textView.selectedRange = clamp(selection, to: textView.text.utf16.count)
        }

        private func clamp(_ range: NSRange, to length: Int) -> NSRange {
            let location = min(range.location, length)
            return NSRange(location: location, length: min(range.length, length - location))
        }
    }
}
#endif
