import SwiftUI
import AppKit
import TeXiumCore

struct SourceEditor: NSViewRepresentable {
    let session: ProjectSession
    let buffer: SourceBuffer
    @AppStorage("editorFont") private var font = "SF Mono"
    @AppStorage("editorSize") private var size = 14.0
    @AppStorage("lineNumbers") private var numbers = true
    @AppStorage("highlighting") private var highlighting = true
    @AppStorage(SyntaxPalette.defaultsKey) private var savedColors = Data()
    @AppStorage("completion") private var completion = true
    @AppStorage("spellCheck") private var spelling = false
    func makeCoordinator() -> Coordinator { Coordinator(session: session, buffer: buffer) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let storage = NSTextStorage(); let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)); container.widthTracksTextView = true; layout.addTextContainer(container)
        let editor = LaTeXTextView(frame: .zero, textContainer: container)
        editor.minSize = NSSize(width: 0, height: 0); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.isRichText = false; editor.allowsUndo = true; editor.usesFindBar = true; editor.isIncrementalSearchingEnabled = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.textContainerInset = NSSize(width: 18, height: 16)
        editor.backgroundColor = .textBackgroundColor; editor.insertionPointColor = .controlAccentColor
        editor.setAccessibilityLabel("LaTeX source editor"); editor.setAccessibilityIdentifier("source-editor")
        editor.session = session; editor.delegate = context.coordinator
        scroll.documentView = editor
        scroll.verticalRulerView = LineNumberRuler(textView: editor); scroll.hasVerticalRuler = true; scroll.rulersVisible = numbers
        context.coordinator.editor = editor; session.editor = editor
        context.coordinator.updating = true
        editor.string = buffer.text; editor.setSelectedRange(buffer.selection)
        context.coordinator.updating = false
        configure(editor); editor.highlight(NSRange(location: 0, length: (editor.string as NSString).length)); editor.rebuildLines()
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? LaTeXTextView else { return }
        let coordinator = context.coordinator
        let changedBuffer = coordinator.buffer !== buffer
        coordinator.buffer = buffer; editor.session = session; session.editor = editor
        configure(editor); scroll.rulersVisible = numbers
        if changedBuffer || editor.string != buffer.text {
            editor.completionController.dismiss(clearSnippet: true)
            coordinator.updating = true
            editor.string = buffer.text
            if changedBuffer { editor.undoManager?.removeAllActions() }
            editor.setSelectedRange(NSRange(location: min(buffer.selection.location, (buffer.text as NSString).length), length: 0))
            editor.highlight(NSRange(location: 0, length: (buffer.text as NSString).length))
            editor.rebuildLines(); coordinator.updating = false
        }
        if coordinator.navigationID != session.navigationID {
            coordinator.navigationID = session.navigationID
            editor.setSelectedRange(buffer.selection); editor.scrollRangeToVisible(buffer.selection); editor.showFindIndicator(for: (editor.string as NSString).lineRange(for: buffer.selection))
            editor.window?.makeFirstResponder(editor)
        }
        if let insertion = session.insertion, coordinator.insertionID != insertion.id {
            coordinator.insertionID = insertion.id
            DispatchQueue.main.async { editor.wrapSelection(before: insertion.before, after: insertion.after) }
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? LaTeXTextView)?.completionController.dismiss(clearSnippet: true)
    }
    private func configure(_ editor: LaTeXTextView) {
        editor.isEditable = !session.operationBusy
        editor.completionEnabled = completion
        if session.operationBusy { editor.completionController.dismiss(clearSnippet: true) }
        let chosen = NSFont(name: font, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        if editor.font != chosen { editor.font = chosen; editor.highlight(NSRange(location: 0, length: (editor.string as NSString).length)) }
        editor.syntaxPalette = SyntaxPalette(data: savedColors)
        editor.highlightEnabled = highlighting; editor.isContinuousSpellCheckingEnabled = spelling
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let session: ProjectSession
        var buffer: SourceBuffer
        weak var editor: LaTeXTextView?
        var updating = false
        var navigationID: UUID?
        var insertionID: UUID?
        var editedRange = NSRange(location: 0, length: 0)
        var originalRange = NSRange(location: 0, length: 0)
        init(session: ProjectSession, buffer: SourceBuffer) { self.session = session; self.buffer = buffer }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if !session.operationBusy { editor?.completionController.willReplace(affectedCharRange, with: replacementString ?? "") }
            originalRange = affectedCharRange
            editedRange = NSRange(location: affectedCharRange.location, length: (replacementString as NSString?)?.length ?? 0); return !session.operationBusy
        }
        func textDidChange(_ notification: Notification) {
            guard !updating, let editor else { return }
            buffer.text = editor.string; buffer.selection = editor.selectedRange()
            let count = (editor.string as NSString).length
            let range = NSRange(location: min(editedRange.location, count), length: min(editedRange.length, max(0, count - editedRange.location)))
            editor.highlight((editor.string as NSString).lineRange(for: range)); editor.updateLines(replacing: originalRange, inserted: range)
            session.edited(buffer)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let editor else { return }
            buffer.selection = editor.selectedRange(); editor.needsDisplay = true
            editor.completionController.selectionChanged()
            editor.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

@MainActor final class LaTeXTextView: NSTextView {
    weak var session: ProjectSession?
    lazy var completionController = EditorCompletionController(editor: self)
    var completionEnabled = true {
        didSet { if !completionEnabled { completionController.dismiss(clearSnippet: true) } }
    }
    override func keyDown(with event: NSEvent) {
        if !completionController.handle(event) { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        completionController.dismiss(clearSnippet: true); super.mouseDown(with: event)
    }
    override func resignFirstResponder() -> Bool {
        completionController.dismiss(clearSnippet: true); return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { completionController.dismiss(clearSnippet: true) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func complete(_ sender: Any?) { completionController.request(explicit: true) }
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender); completionController.request()
    }
    func insertCompletionText(_ text: String, range: NSRange) {
        breakUndoCoalescing(); super.insertText(text, replacementRange: range); breakUndoCoalescing()
    }
    var highlightEnabled = true {
        didSet { if oldValue != highlightEnabled { highlight(NSRange(location: 0, length: (string as NSString).length)) } }
    }
    var syntaxPalette = SyntaxPalette() {
        didSet { if oldValue != syntaxPalette { highlight(NSRange(location: 0, length: (string as NSString).length)) } }
    }
    var lineStarts: [Int] = [0]
    func highlight(_ input: NSRange) {
        guard let storage = textStorage else { return }
        LaTeXSyntaxHighlighter.apply(to: storage, range: input, palette: syntaxPalette, enabled: highlightEnabled)
    }
    func rebuildLines() {
        lineStarts = [0]
        for (i, character) in string.utf16.enumerated() where character == 10 { lineStarts.append(i + 1) }
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    func updateLines(replacing oldRange: NSRange, inserted: NSRange) {
        let delta = inserted.length - oldRange.length
        let prefix = lineStarts.prefix { $0 <= oldRange.location }
        let suffix = lineStarts.drop(while: { $0 <= NSMaxRange(oldRange) }).map { $0 + delta }
        let replacement = (string as NSString).substring(with: inserted)
        let additions = replacement.utf16.enumerated().compactMap { $0.element == 10 ? inserted.location + $0.offset + 1 : nil }
        lineStarts = Array(prefix) + additions + suffix
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard UserDefaults.standard.object(forKey: "currentLine") as? Bool ?? true, let layoutManager, let textContainer, selectedRange().length == 0, !string.isEmpty else { return }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(selectedRange().location, (string as NSString).length - 1))
        var line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        line.origin.y += textContainerOrigin.y; line.origin.x = 0; line.size.width = bounds.width
        NSColor.controlAccentColor.withAlphaComponent(0.045).setFill(); line.fill()
        _ = textContainer
    }
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString; let range = selectedRange(); let line = ns.substring(with: ns.lineRange(for: NSRange(location: range.location, length: 0)))
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let newline = session?.currentBuffer?.file.lineEnding ?? "\n"
        let begin = try! NSRegularExpression(pattern: #"\\begin\{([^}]+)\}\s*$"#)
        let lineStart = ns.lineRange(for: range).location
        let before = ns.substring(with: NSRange(location: lineStart, length: range.location - lineStart)) as NSString
        if let match = begin.firstMatch(in: before as String, range: NSRange(location: 0, length: before.length)) {
            let environment = before.substring(with: match.range(at: 1)); let closing = "\\end{\(environment)}"
            let prefix = newline + indent + indentation
            let suffix = ns.substring(from: NSMaxRange(range)).contains(closing) ? "" : newline + indent + closing
            super.insertText(prefix + suffix, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: 0))
        } else { insertText(newline + indent, replacementRange: range) }
    }
    private var indentation: String {
        let width = max(1, UserDefaults.standard.integer(forKey: "tabWidth") == 0 ? 4 : UserDefaults.standard.integer(forKey: "tabWidth"))
        return UserDefaults.standard.object(forKey: "useSpaces") as? Bool ?? true ? String(repeating: " ", count: width) : "\t"
    }
    override func insertTab(_ sender: Any?) {
        insertText(indentation, replacementRange: selectedRange())
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let text = insertString as? String else { super.insertText(insertString, replacementRange: replacementRange); return }
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let enabled = UserDefaults.standard.object(forKey: "autoClose") as? Bool ?? true
        let closing = ["{": "}", "[": "]", "(": ")"]
        let ns = string as NSString; var backslashes = 0; var index = range.location
        while index > 0 && ns.character(at: index - 1) == 92 { backslashes += 1; index -= 1 }
        if enabled, backslashes % 2 == 0, let end = closing[text] {
            let selected = (string as NSString).substring(with: range)
            super.insertText(text + selected + end, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + 1, length: (selected as NSString).length))
        } else if enabled, ["}", "]", ")"].contains(text), range.length == 0, range.location < (string as NSString).length, (string as NSString).substring(with: NSRange(location: range.location, length: 1)) == text {
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
        } else { super.insertText(text, replacementRange: replacementRange) }
        if ["}", "]", ")"].contains(text) { showMatchingBrace() }
        if text.count == 1 && !text.contains("\n") && !text.contains("\r") { completionController.request() }
    }
    func wrapSelection(before: String, after: String) {
        window?.makeFirstResponder(self)
        let range = selectedRange(); let chosen = (string as NSString).substring(with: range)
        let newline = session?.currentBuffer?.file.lineEnding ?? "\n"
        let prefix = before.replacingOccurrences(of: "\n", with: newline); let suffix = after.replacingOccurrences(of: "\n", with: newline)
        // Bypass automatic brace closure; this is already a complete insertion.
        super.insertText(prefix + chosen + suffix, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: (chosen as NSString).length))
        undoManager?.setActionName("Insert LaTeX")
    }
    func toggleComment() {
        let ns = string as NSString; let range = ns.lineRange(for: selectedRange()); let block = ns.substring(with: range)
        let lines = block.components(separatedBy: "\n")
        let nonempty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let remove = !nonempty.isEmpty && nonempty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("%") }
        let changed = lines.map { line -> String in
            if line.isEmpty { return line }
            if remove, let index = line.firstIndex(of: "%") { var copy = line; copy.remove(at: index); return copy }
            return "%" + line
        }.joined(separator: "\n")
        super.insertText(changed, replacementRange: range)
        setSelectedRange(NSRange(location: range.location, length: (changed as NSString).length)); undoManager?.setActionName("Toggle Comment")
    }
    func showMatchingBrace() {
        let ns = string as NSString; let cursor = selectedRange().location
        guard cursor > 0, cursor <= ns.length else { return }
        let end = ns.character(at: cursor - 1); let pairs: [UInt16: UInt16] = [125: 123, 93: 91, 41: 40]
        guard let begin = pairs[end] else { return }; var depth = 1
        if cursor < 2 { return }
        for i in stride(from: cursor - 2, through: max(0, cursor - 20_000), by: -1) {
            let c = ns.character(at: i)
            if i > 0 && ns.character(at: i - 1) == 92 { continue }
            if c == end { depth += 1 }; if c == begin { depth -= 1 }
            if depth == 0 { showFindIndicator(for: NSRange(location: i, length: 1)); break }
        }
    }
    func goToMatchingEnvironment() {
        guard let range = LaTeXParser.matchingEnvironment(at: selectedRange().location, in: string) else { NSSound.beep(); return }
        setSelectedRange(range); scrollRangeToVisible(range); showFindIndicator(for: range)
    }
}

@MainActor final class LineNumberRuler: NSRulerView {
    weak var editor: LaTeXTextView?
    init(textView: LaTeXTextView) { editor = textView; super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler); clientView = textView; ruleThickness = 52; textView.rebuildLines() }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let visible = editor.visibleRect; let origin = editor.textContainerOrigin
        let glyphs = layout.glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(10, (editor.font?.pointSize ?? 14) - 2), weight: .regular)
        let ns = editor.string as NSString
        for (index, start) in editor.lineStarts.enumerated() where start >= max(0, characters.location - 200) && start <= NSMaxRange(characters) {
            guard start < ns.length else { continue }
            let glyph = layout.glyphIndexForCharacter(at: start); let lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = lineRect.minY + origin.y - visible.minY + 1
            let label = "\(index + 1)" as NSString
            let selected = NSLocationInRange(editor.selectedRange().location, ns.lineRange(for: NSRange(location: start, length: 0)))
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: selected ? NSColor.labelColor : NSColor.tertiaryLabelColor]
            label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attributes).width - 12, y: y), withAttributes: attributes)
        }
    }
}
