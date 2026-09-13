import SwiftUI
import AppKit

struct NativeTextDisplay: NSViewRepresentable {
    let text: String
    var diff = false
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        let view = NSTextView(); view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular); view.textContainerInset = NSSize(width: 12, height: 12)
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]; view.usesFindBar = true
        view.backgroundColor = .textBackgroundColor; view.setAccessibilityLabel(diff ? "Revision diff" : "Text output")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let selected = view.selectedRange(); view.string = text; view.textColor = .textColor
        if diff, let storage = view.textStorage {
            let ns = text as NSString; var location = 0
            for line in text.components(separatedBy: "\n") {
                let length = (line as NSString).length
                if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix("@@") {
                    let color: NSColor = line.hasPrefix("+") ? .systemGreen : line.hasPrefix("-") ? .systemRed : .systemBlue
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: location, length: min(length, ns.length - location)))
                }
                location += length + 1
            }
        }
        view.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
    }
}
