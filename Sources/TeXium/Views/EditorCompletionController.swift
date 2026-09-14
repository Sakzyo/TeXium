import AppKit
import TeXiumCore

/// Transient editor UI only. Project symbols remain owned by ProjectSession.
@MainActor final class EditorCompletionController {
    weak var editor: LaTeXTextView?
    private let popup = CompletionPopup()
    private var task: Task<Void, Never>?
    private var result: CompletionResult?
    private var requestID = UUID()
    private var snippetStops: [Int] = []
    private var activeStop = 0
    var isVisible: Bool { popup.isVisible }

    init(editor: LaTeXTextView) {
        self.editor = editor
        popup.onChoose = { [weak self] in self?.accept($0) }
        popup.onDismiss = { [weak self] in self?.dismiss() }
    }
    func dismiss(clearSnippet: Bool = false) {
        requestID = UUID(); task?.cancel(); task = nil; result = nil; popup.close()
        if clearSnippet { snippetStops = []; activeStop = 0 }
    }
    func refreshIfVisible() { if isVisible { request() } }
    func request(explicit: Bool = false) {
        task?.cancel()
        guard let editor, editor.completionEnabled, editor.isEditable, !editor.hasMarkedText(),
              editor.selectedRange().length == 0, editor.window?.firstResponder === editor,
              let session = editor.session, let file = session.currentBuffer?.path,
              ["tex", "sty", "cls"].contains((file as NSString).pathExtension.lowercased()) else { dismiss(); return }
        let source = editor.string; let selection = editor.selectedRange()
        let project = session.completionProject
        let live = Dictionary(uniqueKeysWithValues: session.buffers.values.map { ($0.path, $0.text) })
        let files = session.files.map(\.path)
        let id = UUID(); requestID = id
        task = Task { [weak self, weak editor] in
            do { try await Task.sleep(for: .milliseconds(explicit ? 0 : 90)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                LaTeXCompletion.suggestions(in: source, at: selection.location, file: file, project: project, liveBuffers: live, files: files, explicit: explicit)
            }.value
            guard !Task.isCancelled, let self, let editor, self.requestID == id, editor.string == source,
                  editor.selectedRange() == selection, editor.window?.firstResponder === editor,
                  editor.completionEnabled, editor.isEditable, !editor.hasMarkedText() else { return }
            self.result = result
            if let result { self.popup.show(result, for: editor) } else { self.popup.close() }
        }
    }
    func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control), !modifiers.contains(.command), event.keyCode == 49 { request(explicit: true); return true }
        if modifiers.contains(.command) { dismiss(clearSnippet: true); return false }
        if event.keyCode == 53 { let visible = isVisible; dismiss(clearSnippet: true); return visible }
        if isVisible, !modifiers.contains(.control), !modifiers.contains(.option) {
            switch event.keyCode {
            case 125: popup.move(1); return true
            case 126: popup.move(-1); return true
            case 36, 76: accept(popup.selectedIndex); return true
            case 48 where !modifiers.contains(.shift): accept(popup.selectedIndex); return true
            default: break
            }
        }
        if event.keyCode == 48, !modifiers.contains(.control), !modifiers.contains(.option), advanceSnippet(backwards: modifiers.contains(.shift)) { return true }
        return false
    }
    func selectionChanged() {
        dismiss()
        guard let editor, let first = snippetStops.first, let last = snippetStops.last else { return }
        if editor.selectedRange().location < first || NSMaxRange(editor.selectedRange()) > last { snippetStops = [] }
    }
    func willReplace(_ range: NSRange, with text: String) {
        guard let first = snippetStops.first, let last = snippetStops.last else { return }
        guard range.location >= first, NSMaxRange(range) <= last else { snippetStops = []; return }
        let delta = (text as NSString).length - range.length
        for index in snippetStops.indices where index > activeStop {
            if snippetStops[index] >= NSMaxRange(range) { snippetStops[index] += delta }
            else { snippetStops = []; return }
        }
    }
    private func accept(_ index: Int) {
        guard let editor, editor.isEditable, let result, result.items.indices.contains(index) else { return }
        let item = result.items[index]
        dismiss()
        editor.insertCompletionText(item.insertion, range: result.range)
        let base = result.range.location
        if !item.stops.isEmpty { snippetStops = item.stops.map { base + $0 }; activeStop = 0 }
        let cursor = item.stops.first.map { base + $0 } ?? base + (item.insertion as NSString).length
        editor.setSelectedRange(NSRange(location: cursor, length: 0)); editor.scrollRangeToVisible(editor.selectedRange())
        editor.undoManager?.setActionName("Complete LaTeX")
        // A command snippet immediately opens its label/citation choices.
        if !item.stops.isEmpty { request() }
    }
    private func advanceSnippet(backwards: Bool) -> Bool {
        guard let editor, !snippetStops.isEmpty else { return false }
        let next = activeStop + (backwards ? -1 : 1)
        guard snippetStops.indices.contains(next) else { return false }
        let position = snippetStops[next]
        guard position <= (editor.string as NSString).length else { snippetStops = []; return false }
        dismiss(); activeStop = next
        editor.setSelectedRange(NSRange(location: position, length: 0))
        if next == snippetStops.count - 1 { snippetStops = [] } else { request() }
        return true
    }
}
