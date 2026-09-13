import SwiftUI
import AppKit
import TeXiumCore

struct ProjectSessionFocus: FocusedValueKey { typealias Value = ProjectSession }
extension FocusedValues {
    var projectSession: ProjectSession? { get { self[ProjectSessionFocus.self] } set { self[ProjectSessionFocus.self] = newValue } }
}
struct TeXiumCommands: Commands {
    let library: ProjectLibrary
    @FocusedValue(\.projectSession) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var issueIndex = 0
    var body: some Commands {
        fileCommands
        workspaceCommands
        writingCommands
    }
    @CommandsBuilder private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { openWindow(id: "browser"); library.createRequested = true }.keyboardShortcut("n")
            Button("New File…") { session?.sheet = .newFile }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(session == nil)
            Button("Open Project…") { if let url = library.chooseProject() { library.remember(url); openWindow(id: "project", value: url.path) } }.keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(library.recents.prefix(15)) { recent in Button(recent.name) { do { let url = try library.resolve(recent); library.remember(url); openWindow(id: "project", value: url.path) } catch { library.error = error.localizedDescription } } }
            }
            Divider()
            Button("Project Browser") { openWindow(id: "browser") }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save All") { Task { do { try await session?.saveAll() } catch { session?.present(error) } } }.keyboardShortcut("s").disabled(session == nil)
            Button("Duplicate File") { if let path = session?.selected { Task { await session?.duplicateItem(path) } } }.disabled(session?.selected == nil)
            Divider()
            Button("Import Files…") { session?.importFiles() }.disabled(session == nil)
            Button("Export Source…") { session?.sheet = .export }.disabled(session == nil)
            Button("Export PDF…") { session?.exportPDF() }.disabled(session?.pdfURL == nil)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { find() }.keyboardShortcut("f")
            Button("Find in Project…") { session?.sheet = .search }.keyboardShortcut("f", modifiers: [.command, .option]).disabled(session == nil)
            Button("Complete LaTeX") { session?.editor?.complete(nil) }.keyboardShortcut(.escape, modifiers: [.control]).disabled(session?.currentBuffer == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Navigator") { session?.showNavigator.toggle() }.keyboardShortcut("s", modifiers: [.command, .control]).disabled(session == nil)
            Button("Toggle PDF Preview") { if let session { session.layout = session.layout == "Source" ? "Both" : "Source" } }.keyboardShortcut("p", modifiers: [.command, .option]).disabled(session == nil)
            Button("Toggle Inspector") { session?.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option]).disabled(session == nil)
            Button("Show Outline") { session?.inspectorTab = "Outline"; session?.showInspector = true }.disabled(session == nil)
            Divider()
            Button("Increase Editor Font") { let defaults = UserDefaults.standard; defaults.set((defaults.object(forKey: "editorSize") as? Double ?? 14) + 1, forKey: "editorSize") }.keyboardShortcut("+")
            Button("Decrease Editor Font") { let defaults = UserDefaults.standard; defaults.set(max(8, (defaults.object(forKey: "editorSize") as? Double ?? 14) - 1), forKey: "editorSize") }.keyboardShortcut("-")
        }
    }
    @CommandsBuilder private var workspaceCommands: some Commands {
        CommandMenu("Navigate") {
            Button("Go to Line…") { session?.sheet = .goToLine }.keyboardShortcut("l").disabled(session?.currentBuffer == nil)
            Button("Go to Matching Environment") { session?.editor?.goToMatchingEnvironment() }.keyboardShortcut("m", modifiers: [.command, .option]).disabled(session?.currentBuffer == nil)
            Button("Show in PDF") { session?.showInPDF() }.keyboardShortcut("j", modifiers: [.command, .shift]).disabled(session?.pdfURL == nil)
            Button("Focus Source Editor") { if let editor = session?.editor { editor.window?.makeFirstResponder(editor) } }.keyboardShortcut("j", modifiers: [.command, .option])
            Divider()
            Button("Next Issue") { navigateIssue(1) }.keyboardShortcut("'", modifiers: [.command]).disabled(session?.diagnostics.isEmpty != false)
            Button("Previous Issue") { navigateIssue(-1) }.keyboardShortcut("'", modifiers: [.command, .shift]).disabled(session?.diagnostics.isEmpty != false)
        }
        CommandMenu("Project") {
            Menu("Main Document") { if let session { ForEach(session.files.filter { $0.path.hasSuffix(".tex") }) { file in Button(file.path + (session.configuration.mainFile == file.path ? " ✓" : "")) { session.configuration.mainFile = file.path } } } }
            Button("New Folder…") { session?.sheet = .newFolder }.disabled(session == nil)
            Button("Reveal Project in Finder") { if let root = session?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) } }.disabled(session == nil)
            Divider()
            Button("Take Snapshot…") { session?.sheet = .snapshot }.keyboardShortcut("s", modifiers: [.command, .option]).disabled(session == nil)
            Button("Show History") { session?.inspectorTab = "History"; session?.showInspector = true }.disabled(session == nil)
            Button("Add Personal Note…") { session?.sheet = .note }.disabled(session == nil)
            Button("Word Count") { session?.countWords() }.disabled(session == nil)
        }
        CommandMenu("Typeset") {
            Button("Compile") { session?.compile() }.keyboardShortcut("r").disabled(session == nil || session?.building == true)
            Button("Stop Compilation") { session?.stopBuild() }.keyboardShortcut(".").disabled(session?.building != true)
            Button("Compile from Scratch") { session?.compile(scratch: true) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(session == nil || session?.building == true)
            Button("Check Draft (pdfLaTeX)") { session?.compile(draft: true) }.disabled(session?.configuration.engine != .pdfLaTeX || session?.building == true)
            Toggle("Automatic Compilation", isOn: Binding(get: { session?.configuration.automatic ?? false }, set: { session?.configuration.automatic = $0 })).disabled(session == nil)
            Divider()
            Menu("Compiler") { ForEach(TeXEngine.allCases) { engine in Button(engine.title) { session?.configuration.engine = engine } } }.disabled(session == nil)
            Menu("Shell Escape") { ForEach(ShellPolicy.allCases, id: \.self) { policy in Button(policy.rawValue.capitalized + (session?.configuration.shellPolicy == policy ? " ✓" : "")) { session?.setShellPolicy(policy) } } }.disabled(session == nil)
            Button("Clear Auxiliary Files") { guard let session else { return }; let root = session.root; Task { do { try await Task.detached { try CompilationService.clearAuxiliary(root: root) }.value; session.buildStatus = "Auxiliary files cleared" } catch { session.present(error) } } }.disabled(session == nil || session?.building == true)
            Button("Custom Build Command…") { session?.sheet = .customBuild }.disabled(session == nil)
            Button("LaTeX Settings…") { openSettings() }
        }
    }
    @CommandsBuilder private var writingCommands: some Commands {
        CommandMenu("Format") {
            Button("Bold") { session?.insert("\\textbf{", after: "}") }.keyboardShortcut("b")
            Button("Italic") { session?.insert("\\textit{", after: "}") }.keyboardShortcut("i")
            Button("Emphasis") { session?.insert("\\emph{", after: "}") }
            Divider()
            Button("Section") { session?.insert("\\section{", after: "}\n") }
            Button("Subsection") { session?.insert("\\subsection{", after: "}\n") }
            Button("Itemized List") { session?.insert("\\begin{itemize}\n  \\item ", after: "\n\\end{itemize}\n") }
            Button("Numbered List") { session?.insert("\\begin{enumerate}\n  \\item ", after: "\n\\end{enumerate}\n") }
            Divider()
            Button("Comment / Uncomment") { session?.editor?.toggleComment() }.keyboardShortcut("/")
        }
        CommandMenu("Insert") {
            Button("Equation…") { session?.sheet = .equation }
            Button("Inline Math") { session?.insert("$", after: "$") }
            Button("Display Math") { session?.insert("\\[\n", after: "\n\\]") }
            Button("Figure…") { session?.sheet = .figure }
            Button("Table…") { session?.sheet = .table }
            Button("Symbol…") { session?.sheet = .symbols }.keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Citation…") { session?.inspectorTab = "References"; session?.showInspector = true }
            Menu("Cross Reference") { if let session { ForEach(session.labels, id: \.self) { key in Button(key) { session.insert("\\ref{\(key)}") } } } }
            Button("Link") { session?.insert("\\href{https://}{", after: "}") }
        }
        CommandMenu("Bibliography") {
            Button("Browse References") { session?.inspectorTab = "References"; session?.showInspector = true }
            Button("Paste BibTeX…") { session?.sheet = .pasteBib }
            Button("Import Bibliography…") { session?.importFiles() }
            Button("Refresh References") { Task { await session?.refreshIndex() } }
        }
        CommandGroup(replacing: .help) {
            Button("TeXium Help") { let alert = NSAlert(); alert.messageText = "Write and typeset locally"; alert.informativeText = "Open a LaTeX folder or create a project. Choose a main .tex file, edit, then press ⌘R to compile.\n\n⌘F Find · ⌥⌘F Project search\n⌘⇧J Source → PDF\n⌘-click PDF → Source\nEsc Native completion\n⌘/ Toggle comment\n\nRequires a local TeX distribution with latexmk. Settings → LaTeX tests your installation."; alert.runModal() }
        }
    }
    private func find() {
        let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
    }
    private func navigateIssue(_ step: Int) {
        guard let session, !session.diagnostics.isEmpty else { return }
        issueIndex = (issueIndex + step + session.diagnostics.count) % session.diagnostics.count
        session.navigate(session.diagnostics[issueIndex])
    }
}
