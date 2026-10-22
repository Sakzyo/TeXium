import AppKit
import TeXiumCore

@MainActor final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel = CompletionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let table = CompletionTable()
    private let heading = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private var items: [CompletionItem] = []
    private var kind: CompletionKind = .command
    var onChoose: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var isVisible: Bool { panel.isVisible }
    var selectedIndex: Int { table.selectedRow }

    override init() {
        super.init()
        panel.isReleasedWhenClosed = false; panel.hasShadow = true; panel.hidesOnDeactivate = true
        // Shown on nearly every keystroke: no fade, and a clear window so the
        // rounded material defines the shape (and shadow) instead of a square backing.
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.animationBehavior = .none
        panel.setAccessibilityLabel("LaTeX suggestions")
        let content = NSVisualEffectView()
        content.material = .menu; content.blendingMode = .behindWindow; content.state = .active
        content.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        panel.contentView = content
        heading.font = .systemFont(ofSize: 11, weight: .semibold); heading.textColor = .secondaryLabelColor
        let footer = NSTextField(labelWithString: "↑↓ Select    Tab / Return Insert    Esc Dismiss")
        footer.font = .systemFont(ofSize: 10); footer.textColor = .tertiaryLabelColor
        let border = CompletionBorder(radius: Self.cornerRadius)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion")))
        table.headerView = nil; table.rowHeight = 43; table.intercellSpacing = .zero
        table.style = .plain; table.backgroundColor = .clear; table.selectionHighlightStyle = .regular
        table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(choose)
        table.setAccessibilityIdentifier("latex-completions"); table.setAccessibilityLabel("LaTeX suggestions")
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        for view in [heading, scroll, footer, border] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: content.leadingAnchor), border.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            border.topAnchor.constraint(equalTo: content.topAnchor), border.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 9), heading.heightAnchor.constraint(equalToConstant: 16),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -5),
            footer.leadingAnchor.constraint(equalTo: heading.leadingAnchor), footer.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8), footer.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func show(_ result: CompletionResult, for editor: NSTextView) {
        guard let parent = editor.window, let screen = parent.screen else { return }
        let old = items.indices.contains(table.selectedRow) ? items[table.selectedRow].insertion : nil
        items = result.items; kind = result.kind; heading.stringValue = result.kind.title + " · \(items.count)"
        table.reloadData()
        let selected = old.flatMap { value in items.firstIndex { $0.insertion == value } } ?? 0
        table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false); table.scrollRowToVisible(selected)
        let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(470, available.width)
        let height = min(CGFloat(min(items.count, 7)) * table.rowHeight + 58, available.height)
        let x = max(available.minX, min(caret.minX, available.maxX - width))
        let below = caret.minY - height - 3
        let y = below >= available.minY ? below : min(caret.maxY + 3, available.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.invalidateShadow()
        if panel.parent !== parent {
            close(); parent.addChildWindow(panel, ordered: .above)
        }
        if !panel.isVisible {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(dismiss), name: name, object: parent)
            }
            if let clip = editor.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(dismiss), name: NSView.boundsDidChangeNotification, object: clip)
            }
        }
        panel.orderFront(nil)
    }
    func move(_ offset: Int) {
        guard !items.isEmpty else { return }
        let row = max(0, min(items.count - 1, table.selectedRow + offset))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
    }
    func close() {
        NotificationCenter.default.removeObserver(self)
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
    }
    @objc private func dismiss() { onDismiss?() }
    @objc private func choose() { if table.selectedRow >= 0 { onChoose?(table.selectedRow) } }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { CompletionRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = CompletionCell()
        let title = NSTextField(labelWithString: item.title)
        title.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail; title.setAccessibilityIdentifier("completion-" + (kind == .environment ? item.title : item.insertion))
        let detail = NSTextField(labelWithString: item.detail.replacingOccurrences(of: "\n", with: " "))
        detail.font = .systemFont(ofSize: 10.5); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        cell.textField = title; cell.detail = detail; cell.toolTip = item.title + "\n" + item.detail
        for field in [title, detail] { field.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(field) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])
        return cell
    }
    private static let cornerRadius: CGFloat = 10
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill(); return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Hairline edge so the material separates from light editor backgrounds.
private final class CompletionBorder: NSView {
    private let radius: CGFloat
    init(radius: CGFloat) { self.radius = radius; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let width = 1 / (window?.backingScaleFactor ?? 2)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: radius - width / 2, yRadius: radius - width / 2)
        path.lineWidth = width
        NSColor.separatorColor.setStroke(); path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func viewDidChangeBackingProperties() { needsDisplay = true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
/// The panel never becomes key, so AppKit would draw a gray, unemphasized
/// selection. Completion lists read as the active focus, like Xcode's.
private final class CompletionRow: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}
private final class CompletionCell: NSTableCellView {
    weak var detail: NSTextField?
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let emphasized = backgroundStyle == .emphasized
            textField?.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
            detail?.textColor = emphasized ? .alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
        }
    }
}

private final class CompletionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class CompletionTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}
