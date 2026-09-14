import AppKit
import TeXiumCore

/// Transient editor UI only. Project symbols remain owned by ProjectSession.
@MainActor final class EditorCompletionController {
    weak var editor: LaTeXTextView?
    private let popup = CompletionPopup()
    private var task: Task<Void, Never>?
    private var result: CompletionResult?
    private var requestID = UUID()
    private var snippet: CompletionSnippetSession?
    var isVisible: Bool { popup.isVisible }

    init(editor: LaTeXTextView) {
        self.editor = editor
        popup.onChoose = { [weak self] in self?.accept($0) }
        popup.onDismiss = { [weak self] in self?.dismiss() }
    }
    func dismiss(clearSnippet: Bool = false) {
        requestID = UUID(); task?.cancel(); task = nil; result = nil; popup.close()
        if clearSnippet { snippet = nil }
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
        let formatting = CompletionFormatting(indentation: editor.indentation, lineEnding: session.currentBuffer?.file.lineEnding ?? "\n")
        let id = UUID(); requestID = id
        task = Task { [weak self, weak editor] in
            do { try await Task.sleep(for: .milliseconds(explicit ? 0 : 90)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                LaTeXCompletion.suggestions(in: source, at: selection.location, file: file, project: project, liveBuffers: live, files: files, explicit: explicit, formatting: formatting)
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
        guard let editor else { return }
        if snippet?.trackSelection(editor.selectedRange()) == false { snippet = nil }
    }
    func willReplace(_ range: NSRange, with text: String) {
        if snippet?.replace(range, with: text) == false { snippet = nil }
    }
    private func accept(_ index: Int) {
        guard let editor, editor.isEditable, let result, result.items.indices.contains(index) else { return }
        let item = result.items[index]
        dismiss()
        editor.insertCompletionText(item.insertion, range: result.range)
        let base = result.range.location
        if !item.fields.isEmpty { snippet = CompletionSnippetSession(fields: item.fields, base: base) }
        let selection = item.fields.first.map { NSRange(location: base + $0.location, length: $0.length) }
            ?? NSRange(location: base + (item.insertion as NSString).length, length: 0)
        editor.setSelectedRange(selection); editor.scrollRangeToVisible(selection)
        editor.undoManager?.setActionName("Complete LaTeX")
        // A command snippet immediately opens its label/citation choices.
        if !item.stops.isEmpty { request() }
    }
    private func advanceSnippet(backwards: Bool) -> Bool {
        guard let editor, let selection = snippet?.advance(backwards: backwards) else { return false }
        guard NSMaxRange(selection) <= (editor.string as NSString).length else { snippet = nil; return false }
        dismiss()
        editor.setSelectedRange(selection); editor.scrollRangeToVisible(selection)
        if snippet?.isAtEnd == true { snippet = nil } else { request() }
        return true
    }
}
