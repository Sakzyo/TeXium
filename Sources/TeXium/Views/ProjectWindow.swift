import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TeXiumCore

struct ProjectWindow: View {
    @State private var session: ProjectSession
    let library: ProjectLibrary
    @State private var visibility: NavigationSplitViewVisibility = .all
    @SceneStorage("projectLayout") private var savedLayout = "Both"
    @SceneStorage("projectInspector") private var savedInspector = true
    @SceneStorage("projectNavigator") private var savedNavigator = true
    init(root: URL, library: ProjectLibrary) { _session = State(initialValue: ProjectSession(root: root)); self.library = library }
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            ProjectNavigator(session: session).navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 380).disabled(session.operationBusy)
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    if session.layout != "PDF" { EditorPane(session: session).frame(minWidth: 320) }
                    if session.layout != "Source" { PDFPreview(session: session).frame(minWidth: 290) }
                }
                Divider()
                statusBar
            }
        }
        .inspector(isPresented: $session.showInspector) {
            ProjectInspector(session: session).inspectorColumnWidth(min: 240, ideal: 280, max: 500)
        }
        .frame(minWidth: 880, minHeight: 560)
        .navigationTitle(session.title)
        .navigationSubtitle(session.configuration.mainFile)
        .toolbar { toolbar }
        .focusedSceneValue(\.projectSession, session)
        .background(WindowLifecycle(session: session))
        .task { session.layout = savedLayout; session.showInspector = savedInspector; session.showNavigator = savedNavigator; visibility = savedNavigator ? .all : .detailOnly; await session.load(); library.remember(session.root) }
        .onChange(of: session.layout) { _, value in savedLayout = value }
        .onChange(of: session.showInspector) { _, value in savedInspector = value }
        .onChange(of: session.showNavigator) { _, value in visibility = value ? .all : .detailOnly }
        .onChange(of: visibility) { _, value in savedNavigator = value != .detailOnly; session.showNavigator = savedNavigator }
        .onChange(of: session.configuration) { _, _ in session.persistPreferences() }
        .sheet(item: $session.sheet) { sheet in WorkspaceSheets(session: session, sheet: sheet) }
        .sheet(isPresented: Binding(get: { session.conflictPath != nil }, set: { _ in })) { ConflictSheet(session: session) }
        .alert("TeXium", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
        .alert("Project Update", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })) {
            Button("OK") { session.notice = nil }
        } message: { Text(session.notice ?? "") }
        .alert("Move to Trash?", isPresented: Binding(get: { session.deletePath != nil }, set: { if !$0 { session.deletePath = nil } })) {
            Button("Cancel", role: .cancel) { session.deletePath = nil }
            Button("Move to Trash", role: .destructive) { if let path = session.deletePath { Task { await session.trashItem(path) } }; session.deletePath = nil }
        } message: { Text("\(session.deletePath ?? "This item") will be moved to the Trash. A local history snapshot will be retained.") }
        .alert("Allow Shell Commands for This Project?", isPresented: $session.shellApprovalRequested) {
            Button("Keep Disabled", role: .cancel) {}
            Button("Allow Shell Escape", role: .destructive) { session.configuration.shellPolicy = .enabled; session.persistPreferences() }
        } message: { Text("LaTeX in this project could run arbitrary commands with your account’s permissions. Enable this only for source you trust.") }
        .alert("Recover Unsaved Edits?", isPresented: Binding(get: { !session.recoveryAvailable.isEmpty }, set: { _ in })) {
            Button("Recover Edits") { Task { await session.recoverBuffers() } }
            Button("Keep Files on Disk") { session.recoveryAvailable = [:]; session.writeRecovery() }
        } message: { Text("Recovery copies are available for \(session.recoveryAvailable.count) source files from an earlier session.") }
    }
    private var statusBar: some View {
        HStack(spacing: 14) {
            if session.building || session.operationBusy { ProgressView().controlSize(.small) }
            Image(systemName: session.buildStatus.contains("failed") ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(.secondary)
            Text(session.buildStatus).lineLimit(1).accessibilityIdentifier("build-status")
            if let start = session.buildStarted { TimelineView(.periodic(from: start, by: 1)) { _ in Text("\(Int(Date().timeIntervalSince(start)))s").monospacedDigit() } }
            Spacer()
            if let buffer = session.currentBuffer {
                Text(buffer.dirty ? "Edited" : "Saved")
                Text("Ln \(session.currentLine)").monospacedDigit()
                Text(buffer.file.encoding == .utf8 ? "UTF-8" : "UTF-16")
                Text(buffer.file.lineEnding == "\r\n" ? "CRLF" : "LF")
            }
            if session.isGitRepository { Label(session.gitBranch.isEmpty ? "Git" : session.gitBranch, systemImage: "arrow.triangle.branch") }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 28)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { session.building ? session.stopBuild() : session.compile() } label: { Label(session.building ? "Stop Compilation" : "Compile", systemImage: session.building ? "stop.fill" : "play.fill") }.help(session.building ? "Stop compilation" : "Compile (⌘R)")
            Picker("Compiler", selection: $session.configuration.engine) { ForEach(TeXEngine.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu).frame(width: 110).disabled(session.building)
        }
        ToolbarItem(placement: .principal) {
            Picker("Layout", selection: $session.layout) {
                Label("Source", systemImage: "chevron.left.forwardslash.chevron.right").tag("Source")
                Label("Source and PDF", systemImage: "rectangle.split.2x1").tag("Both")
                Label("PDF", systemImage: "doc.richtext").tag("PDF")
            }.pickerStyle(.segmented).labelStyle(.iconOnly).frame(width: 132)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Show in PDF", systemImage: "arrow.left.arrow.right") { session.showInPDF() }.disabled(session.pdfURL == nil).help("Show source in PDF (⌘⇧J)")
            Button("Search Project", systemImage: "magnifyingglass") { session.sheet = .search }.help("Find in Project (⌥⌘F)")
            Button("Toggle Inspector", systemImage: "sidebar.right") { session.showInspector.toggle() }.help("Show or hide inspector")
        }
    }
}

struct ProjectNavigator: View {
    @Bindable var session: ProjectSession
    @State private var selected: String?
    var body: some View {
        List(selection: $selected) {
            Section(session.title) {
                OutlineGroup(session.nodes, children: \.children) { node in
                    HStack(spacing: 7) {
                        Image(systemName: node.symbol).foregroundStyle(.secondary)
                        Text(node.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if node.path == session.configuration.mainFile { Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(.secondary).help("Main document") }
                        if session.buffers[node.path]?.dirty == true { Image(systemName: "circle.fill").font(.system(size: 5)).accessibilityLabel("Unsaved edits") }
                    }.tag(node.path)
                    .contextMenu { fileMenu(node) }
                    .onDrag { NSItemProvider(object: session.root.appendingPathComponent(node.path) as NSURL) }
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in session.acceptDrop(providers, folder: node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent, move: !NSEvent.modifierFlags.contains(.option)) }
                }
            }
        }.listStyle(.sidebar)
        .onChange(of: selected) { _, path in if let path { Task { await session.select(path) } } }
        .onChange(of: session.selected) { _, path in selected = path }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { session.acceptDrop($0, folder: "", move: !NSEvent.modifierFlags.contains(.option)) }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu { Button("New File…") { session.sheet = .newFile }; Button("New Folder…") { session.sheet = .newFolder }; Button("Import Files…") { session.importFiles() } } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 24)
                Spacer()
                Text("\(session.files.count) files").font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
    }
    @ViewBuilder private func fileMenu(_ file: ProjectFile) -> some View {
        Button("Open") { Task { await session.select(file.path) } }
        if file.path.hasSuffix(".tex") { Button("Set as Main Document") { session.configuration.mainFile = file.path } }
        Divider()
        Button("Rename…") { session.renamePath = file.path; session.sheet = .rename }
        Button("Duplicate") { Task { await session.duplicateItem(file.path) } }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.root.appendingPathComponent(file.path)]) }
        Button("Open Externally") { NSWorkspace.shared.open(session.root.appendingPathComponent(file.path)) }
        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.root.appendingPathComponent(file.path).path, forType: .string) }
        Divider()
        Button("Move to Trash…", role: .destructive) { session.deletePath = file.path }
    }
}

struct EditorPane: View {
    @Bindable var session: ProjectSession
    var body: some View {
        VStack(spacing: 0) {
            if !session.tabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(session.tabs, id: \.self) { path in
                            HStack(spacing: 8) {
                                Button { Task { await session.select(path) } } label: {
                                    HStack(spacing: 6) { Image(systemName: path.hasSuffix(".bib") ? "books.vertical" : "doc.text"); Text((path as NSString).lastPathComponent); if session.buffers[path]?.dirty == true { Text("•") } }
                                }.buttonStyle(.plain)
                                Button("Close File", systemImage: "xmark") { session.closeTab(path) }.labelStyle(.iconOnly).buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary)
                            }.font(.callout).padding(.horizontal, 13).frame(height: 37)
                            .background(session.selected == path ? Color.primary.opacity(0.045) : Color.clear)
                            .overlay(alignment: .bottom) { if session.selected == path { Rectangle().fill(Color.accentColor).frame(height: 2) } }
                            Divider().frame(height: 20)
                        }
                    }
                }
                Divider()
            }
            if let buffer = session.currentBuffer {
                SourceEditor(session: session, buffer: buffer)
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        for provider in providers {
                            _ = provider.loadObject(ofClass: NSURL.self) { value, _ in
                                guard let url = value as? URL else { return }
                                Task { @MainActor in
                                    if (try? ProjectFileSystem.relative(url, to: session.root)) == nil { await session.importURLs([url], folder: "", move: false) }
                                    let path = (try? ProjectFileSystem.relative(url, to: session.root)) ?? url.lastPathComponent
                                    session.insert("\\includegraphics[width=\\linewidth]{\\detokenize{\(path)}}")
                                }
                            }
                        }
                        return !providers.isEmpty
                    }
            } else if let path = session.selected {
                AssetPreview(url: session.root.appendingPathComponent(path))
            } else {
                ContentUnavailableView("Choose a Source File", systemImage: "doc.text", description: Text("Select a file in the navigator, or create a new one."))
            }
        }
    }
}
struct AssetPreview: View {
    let url: URL
    var body: some View {
        if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().padding(24).frame(maxWidth: .infinity, maxHeight: .infinity) }
        else { ContentUnavailableView { Label(url.lastPathComponent, systemImage: "doc") } description: { Text("Use the system’s default application to inspect this resource.") } actions: { Button("Open Externally") { NSWorkspace.shared.open(url) } } }
    }
}
