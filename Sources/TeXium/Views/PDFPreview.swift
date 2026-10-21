import SwiftUI
import PDFKit
import TeXiumCore

struct PDFPreview: View {
    @Bindable var session: ProjectSession
    @State private var page = 1
    @State private var pageCount = 0
    @State private var zoom = 100
    @State private var query = ""
    @State private var thumbnails = UserDefaults.standard.bool(forKey: "pdfThumbnails")
    @State private var matchIndex = 0
    @State private var matches: [PDFSelection] = []
    @State private var searchedQuery: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Preview", systemImage: "doc.richtext").font(.callout.weight(.medium))
                // Lives in the header rather than as a banner, so the page never
                // jumps when the first edit after a build marks the output stale.
                ZStack {
                    if session.stalePDF && session.pdfURL != nil {
                        ViewThatFits(in: .horizontal) {
                            Label(session.building ? "Updating…" : "Outdated", systemImage: "clock.arrow.circlepath")
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .help(session.building ? "Typesetting the updated source…" : "Showing previous output — the source has changed since this PDF was typeset.")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(session.building ? "Typesetting updated source" : "Previous output, source has changed")
                        .transition(.opacity)
                    }
                }.animation(.texiumEaseOut, value: session.stalePDF)
                Spacer(minLength: 8)
                if session.pdfURL != nil { pageControls }
            }.buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 37)
            Divider()
            if session.pdfURL != nil {
                HStack(spacing: 0) {
                    if thumbnails { PDFThumbnails(session: session).frame(width: 100); Divider() }
                    PDFKitView(session: session, page: $page, count: $pageCount, zoom: $zoom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find in PDF", text: $query).textFieldStyle(.plain).onSubmit { find() }
                    if !matches.isEmpty { Text("\(matchIndex + 1) of \(matches.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    else if !query.isEmpty && searchedQuery == query { Text("No matches").font(.caption).foregroundStyle(.secondary) }
                    Button("Next Match", systemImage: "chevron.down") { find(next: true) }.labelStyle(.iconOnly).buttonStyle(.borderless).disabled(query.isEmpty).help("Next match (Return)")
                }.padding(.horizontal, 12).padding(.vertical, 9)
            } else {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 290, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pdf-pane")
    }
    @ViewBuilder private var pageControls: some View {
        HStack(spacing: 6) {
            Button("Previous Page", systemImage: "chevron.up") { session.pdfView?.goToPreviousPage(nil) }.labelStyle(.iconOnly).disabled(page <= 1)
            TextField("Page", value: $page, format: .number).frame(width: 35).multilineTextAlignment(.center).onSubmit { goToPage() }.accessibilityLabel("PDF page number")
            Text("of \(pageCount)").font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize()
            Button("Next Page", systemImage: "chevron.down") { session.pdfView?.goToNextPage(nil) }.labelStyle(.iconOnly).disabled(page >= pageCount)
        }
        Menu {
            Button("Zoom In") { session.pdfView?.zoomIn(nil) }
            Button("Zoom Out") { session.pdfView?.zoomOut(nil) }
            Button("Actual Size") { session.pdfView?.autoScales = false; session.pdfView?.scaleFactor = 1 }
            Button("Fit Page") { session.pdfView?.autoScales = true }
            Button("Fit Width") { fitWidth() }
            Divider()
            Toggle("Thumbnails", isOn: $thumbnails)
            Button("Open in Preview") { if let url = session.pdfURL { NSWorkspace.shared.open(url) } }
            Button("Reveal in Finder") { if let url = session.pdfURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            Button("Export PDF…") { session.exportPDF() }
            Button("Print…") { printPDF() }
        } label: { Text("\(zoom)%").monospacedDigit() }
        .fixedSize()
        .help("Zoom and PDF options")
    }
    @ViewBuilder private var emptyState: some View {
        if session.building {
            ContentUnavailableView {
                Label { Text("Typesetting…") } icon: { ProgressView().controlSize(.large) }
            } description: { Text(session.buildStatus) }
        } else if session.buildStatus.hasPrefix("Build failed") {
            ContentUnavailableView {
                Label("The Build Didn’t Finish", systemImage: "exclamationmark.triangle")
            } description: { Text("Fix the issues listed in Problems, then compile again.") } actions: {
                Button("Show Problems") { session.inspectorTab = "Problems"; session.showInspector = true }
                Button("Compile Project") { session.compile() }
            }
        } else {
            ContentUnavailableView { Label("Your Document, Typeset", systemImage: "doc.richtext") } description: { Text("Compile the project to generate a PDF.\nYour local TeX installation does the rest.") } actions: { Button("Compile Project") { session.compile() } }
        }
    }
    private func goToPage() { if let target = session.pdfView?.document?.page(at: max(0, min(page - 1, pageCount - 1))) { session.pdfView?.go(to: target) } }
    private func fitWidth() {
        guard let view = session.pdfView, let page = view.currentPage else { return }
        view.autoScales = false; view.scaleFactor = max(0.1, (view.bounds.width - 24) / page.bounds(for: .cropBox).width)
    }
    private func find(next: Bool = false) {
        guard let view = session.pdfView, let document = view.document else { return }
        if !next || searchedQuery != query {
            matches = query.isEmpty ? [] : document.findString(query, withOptions: [.caseInsensitive]); matchIndex = 0; searchedQuery = query
        }
        else if !matches.isEmpty { matchIndex = (matchIndex + 1) % matches.count }
        if !matches.isEmpty { view.setCurrentSelection(matches[matchIndex], animate: true); view.go(to: matches[matchIndex]) }
    }
    private func printPDF() {
        guard let document = session.pdfView?.document, let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        operation.run()
    }
}

struct PDFKitView: NSViewRepresentable {
    let session: ProjectSession
    @Binding var page: Int
    @Binding var count: Int
    @Binding var zoom: Int
    @AppStorage("pdfContinuous") private var continuous = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SyncedPDFView {
        let view = SyncedPDFView(); view.autoScales = true; view.displayMode = continuous ? .singlePageContinuous : .singlePage
        view.displaysPageBreaks = true; view.pageBreakMargins = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.backgroundColor = .underPageBackgroundColor; view.session = session; session.pdfView = view
        view.setAccessibilityLabel("Compiled PDF preview")
        context.coordinator.observe(view)
        return view
    }
    func updateNSView(_ view: SyncedPDFView, context: Context) {
        context.coordinator.parent = self; session.pdfView = view
        view.displayMode = continuous ? .singlePageContinuous : .singlePage
        if context.coordinator.revision != session.pdfRevision || context.coordinator.url != session.pdfURL {
            let oldIndex = view.currentPage.flatMap { view.document?.index(for: $0) } ?? max(0, session.savedPDFPage - 1)
            let oldPoint = view.currentDestination?.point; let oldScale = view.scaleFactor; let auto = view.autoScales
            let coordinator = context.coordinator
            coordinator.revision = session.pdfRevision; coordinator.url = session.pdfURL
            coordinator.loadTask?.cancel()
            guard let url = session.pdfURL else { return }
            let hadDocument = view.document != nil
            coordinator.loadTask = Task { @MainActor [weak view] in
                let document = await Task.detached(priority: .userInitiated) {
                    (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
                }.value
                guard !Task.isCancelled, let view, let document else { return }
                view.document = document
                let pageIndex = min(oldIndex, max(0, document.pageCount - 1))
                if let target = document.page(at: pageIndex) {
                    if let oldPoint { view.go(to: PDFDestination(page: target, at: oldPoint)) } else { view.go(to: target) }
                }
                let savedScale = session.savedPDFScale
                view.autoScales = hadDocument ? auto : savedScale == 0
                if !view.autoScales { view.scaleFactor = hadDocument ? oldScale : savedScale }
                count = document.pageCount; page = pageIndex + 1; zoom = Int(view.scaleFactor * 100)
            }
        }
        if let location = session.pdfDestination, context.coordinator.destination != location, let page = view.document?.page(at: location.page - 1) {
            context.coordinator.destination = location
            let bounds = page.bounds(for: .mediaBox)
            let point = NSPoint(x: bounds.minX + location.x, y: bounds.maxY - location.y)
            view.go(to: NSRect(x: point.x - 24, y: point.y - 24, width: 120, height: 70), on: page)
            if let selection = page.selection(for: NSRect(x: point.x - 4, y: point.y - 8, width: 240, height: 22)) { selection.color = .selectedTextBackgroundColor; view.setCurrentSelection(selection, animate: true) }
        }
    }
    @MainActor final class Coordinator: NSObject {
        var parent: PDFKitView
        var revision: UUID?
        var url: URL?
        var destination: PDFLocation?
        var loadTask: Task<Void, Never>?
        init(_ parent: PDFKitView) { self.parent = parent }
        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: .PDFViewPageChanged, object: view)
            NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: .PDFViewScaleChanged, object: view)
        }
        @objc func update(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            Task { @MainActor in
                self.parent.page = view.currentPage.flatMap { view.document?.index(for: $0) }.map { $0 + 1 } ?? 1
                self.parent.count = view.document?.pageCount ?? 0; self.parent.zoom = Int(view.scaleFactor * 100)
                self.parent.session.savedPDFPage = self.parent.page
                self.parent.session.savedPDFScale = view.autoScales ? 0 : view.scaleFactor
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
@MainActor final class SyncedPDFView: PDFView {
    weak var session: ProjectSession?
    private var contextLocation: PDFLocation?
    private func sourceLocation(for event: NSEvent) -> PDFLocation? {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: true), let document else { return nil }
        let converted = convert(point, to: page); let bounds = page.bounds(for: .mediaBox)
        return PDFLocation(page: document.index(for: page) + 1, x: converted.x - bounds.minX, y: bounds.maxY - converted.y)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        contextLocation = sourceLocation(for: event)
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Show Source Here", action: #selector(showContextSource), keyEquivalent: "")
        item.target = self; item.isEnabled = contextLocation != nil; menu.addItem(item)
        return menu
    }
    @objc private func showContextSource() { if let contextLocation { session?.showSource(at: contextLocation) } }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if let location = sourceLocation(for: event) { session?.showSource(at: location); return }
        }
        super.mouseDown(with: event)
    }
}
struct PDFThumbnails: NSViewRepresentable {
    let session: ProjectSession
    func makeNSView(context: Context) -> PDFThumbnailView { let view = PDFThumbnailView(); view.thumbnailSize = NSSize(width: 72, height: 96); return view }
    func updateNSView(_ view: PDFThumbnailView, context: Context) { view.pdfView = session.pdfView }
}
