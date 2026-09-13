import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TeXiumCore

struct ProjectBrowser: View {
    @Bindable var library: ProjectLibrary
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""
    @State private var selection: String?
    @State private var creating = false
    @State private var importing = false
    @State private var cloneURL = ""
    @State private var cloning = false
    @State private var busy = false
    private var projects: [RecentProject] {
        library.recents.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }
            .sorted { $0.favorite != $1.favorite ? $0.favorite : $0.opened > $1.opened }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Recent Projects") {
                    ForEach(projects) { project in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                Text(project.available ? project.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") : "Unavailable").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        } icon: { Image(systemName: project.favorite ? "star.fill" : "folder") }
                        .tag(project.path)
                        .contextMenu {
                            Button("Open Project") { open(project) }
                            Button(project.favorite ? "Unpin" : "Pin") { library.favorite(project) }
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)]) }
                            Button("Rename…") { rename(project) }
                            Button("Duplicate…") { duplicate(project) }
                            Divider()
                            Button("Remove from Recents") { library.remove(project) }
                        }
                        .onTapGesture(count: 2) { open(project) }
                    }
                }
            }.listStyle(.sidebar).searchable(text: $search, prompt: "Find a project")
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 400)
        } detail: {
            VStack(spacing: 20) {
                Image(systemName: "character.book.closed.fill").font(.system(size: 64, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("TeXium").font(.largeTitle.weight(.semibold))
                    Text("A place for your next paper.").font(.title3).foregroundStyle(.secondary)
                }
                if let project = library.recents.first(where: { $0.path == selection }) {
                    VStack(spacing: 6) {
                        Text(project.name).font(.headline)
                        Text("Opened \(project.opened.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        if let modified = project.modified { Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        Button("Open Project") { open(project) }.keyboardShortcut(.return, modifiers: [])
                    }.padding(.top, 8)
                }
                VStack(spacing: 10) {
                    Button { creating = true } label: { Label("Create a Project…", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    Button { chooseProject() } label: { Label("Open an Existing Folder…", systemImage: "folder") }
                }.controlSize(.large)
                Text("Write, typeset, and explore. Entirely on your Mac.").font(.caption).foregroundStyle(.tertiary).padding(.top, 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .toolbar {
            ToolbarItemGroup {
                Button("Open Project", systemImage: "folder") { chooseProject() }
                Button("New Project", systemImage: "plus") { creating = true }
                Menu("Import", systemImage: "square.and.arrow.down") {
                    Button("Import ZIP Project…") { importZIP() }
                    Button("Clone Git Repository…") { cloning = true }
                    Button("Create from Local Template Folder…") { localTemplate() }
                }
            }
        }
        .sheet(isPresented: $creating) { NewProjectSheet { url in library.remember(url); openWindow(id: "project", value: url.path) } }
        .sheet(isPresented: $cloning) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clone a Git Repository").font(.title2)
                TextField("Repository URL", text: $cloneURL).frame(width: 440)
                Text("Uses your installed Git and configured credentials.").font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Cancel") { cloning = false }; Button("Choose Destination…") { clone() }.disabled(cloneURL.isEmpty || busy) }
            }.padding(24)
        }
        .alert("TeXium", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("OK") { library.error = nil } } message: { Text(library.error ?? "") }
        .onChange(of: library.createRequested) { _, requested in if requested { creating = true; library.createRequested = false } }
        .task {
            guard !library.restoredLaunch else { return }
            library.restoredLaunch = true
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--project"), args.count > index + 1 {
                let url = URL(fileURLWithPath: args[index + 1]); library.remember(url); openWindow(id: "project", value: url.path)
            } else if UserDefaults.standard.object(forKey: "reopenProjects") as? Bool ?? true {
                for path in UserDefaults.standard.stringArray(forKey: "openProjectWindows") ?? [] {
                    if let recent = library.recents.first(where: { $0.path == path }), let url = try? library.resolve(recent) {
                        openWindow(id: "project", value: url.path)
                    }
                }
            }
        }
    }
    private func open(_ project: RecentProject) {
        do { let url = try library.resolve(project); library.remember(url); openWindow(id: "project", value: url.path) }
        catch { library.error = error.localizedDescription }
    }
    private func chooseProject() { if let url = library.chooseProject() { library.remember(url); openWindow(id: "project", value: url.path) } }
    private func destination(title: String, name: String) -> URL? {
        let panel = NSSavePanel(); panel.title = title; panel.nameFieldStringValue = name; panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func importZIP() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let zip = panel.url, let target = destination(title: "Import Project", name: zip.deletingPathExtension().lastPathComponent) else { return }
        busy = true
        Task { defer { busy = false }; do { try await Task.detached { try await ArchiveService.importZIP(zip, to: target) }.value; library.remember(target); openWindow(id: "project", value: target.path) } catch { library.error = error.localizedDescription } }
    }
    private func localTemplate() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.title = "Choose a Local Template Folder"
        guard panel.runModal() == .OK, let source = panel.url, let target = destination(title: "Create from Template", name: "Untitled Project") else { return }
        Task { do { try await Task.detached { try await ArchiveService.export(root: source, to: target, preset: .source, zip: false) }.value; library.remember(target); openWindow(id: "project", value: target.path) } catch { library.error = error.localizedDescription } }
    }
    private func clone() {
        guard !cloneURL.hasPrefix("-"), let target = destination(title: "Clone Repository", name: "LaTeX Project") else { return }
        let remote = cloneURL; busy = true
        Task { defer { busy = false }; do { _ = try await GitService.run(["clone", "--", remote, target.path], root: target.deletingLastPathComponent()); cloning = false; library.remember(target); openWindow(id: "project", value: target.path) } catch { library.error = error.localizedDescription } }
    }
    private func duplicate(_ project: RecentProject) {
        guard let target = destination(title: "Duplicate Project", name: project.name + " Copy") else { return }
        let source = URL(fileURLWithPath: project.path)
        Task { do { try await Task.detached { try await ArchiveService.export(root: source, to: target, preset: .source, zip: false) }.value; library.remember(target) } catch { library.error = error.localizedDescription } }
    }
    private func rename(_ project: RecentProject) {
        guard !ProjectSession.openSessions.allObjects.contains(where: { $0.root.path == project.path }) else { library.error = "Close this project’s editor window before renaming its folder."; return }
        guard let target = destination(title: "Rename Project Folder", name: project.name) else { return }
        do { try FileManager.default.moveItem(at: URL(fileURLWithPath: project.path), to: target); library.remove(project); library.remember(target) } catch { library.error = error.localizedDescription }
    }
}

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ProjectTemplate = .article
    @State private var query = ""
    @State private var error: String?
    let created: (URL) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Choose a Starting Point").font(.title2.weight(.semibold)); Spacer() }.padding(24)
            HSplitView {
                List(ProjectTemplate.allCases.filter { query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) }, selection: $selected) { template in
                    Label(template.rawValue, systemImage: template.symbol).tag(template).padding(.vertical, 3)
                }.searchable(text: $query, prompt: "Search templates").frame(width: 210)
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: selected.symbol).font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
                    Text(selected.rawValue).font(.title)
                    Text(selected.detail).foregroundStyle(.secondary)
                    Divider()
                    Text("Standard LaTeX files\nAvailable offline\nReady for your own toolchain").font(.callout).foregroundStyle(.secondary).lineSpacing(8)
                    Spacer()
                }.padding(28).frame(minWidth: 330, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack { Text("Saved as an ordinary folder on your Mac.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Choose Location…") { create() }.keyboardShortcut(.defaultAction) }.padding(16)
        }.frame(width: 680, height: 480)
        .alert("Could Not Create Project", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func create() {
        let panel = NSSavePanel(); panel.title = "Create Project"; panel.nameFieldStringValue = "Untitled " + selected.rawValue; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let root = panel.url else { return }
        let template = selected
        Task { do { try await Task.detached { try TemplateService.create(template, at: root) }.value; created(root); dismiss() } catch { self.error = error.localizedDescription } }
    }
}
