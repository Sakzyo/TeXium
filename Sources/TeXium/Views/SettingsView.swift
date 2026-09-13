import SwiftUI
import TeXiumCore

struct SettingsView: View {
    @AppStorage("editorFont") private var font = "SF Mono"
    @AppStorage("editorSize") private var size = 14.0
    @AppStorage("tabWidth") private var tabWidth = 4
    @AppStorage("useSpaces") private var spaces = true
    @AppStorage("lineNumbers") private var lineNumbers = true
    @AppStorage("autoClose") private var autoClose = true
    @AppStorage("highlighting") private var highlighting = true
    @AppStorage("spellCheck") private var spelling = false
    @AppStorage("completion") private var completion = true
    @AppStorage("currentLine") private var currentLine = true
    @AppStorage("texPath") private var texPath = ""
    @AppStorage("autoCompileDelay") private var delay = 2.0
    @AppStorage("defaultEngine") private var engine = TeXEngine.pdfLaTeX.rawValue
    @AppStorage("pdfContinuous") private var continuous = true
    @AppStorage("pdfThumbnails") private var thumbnails = false
    @AppStorage("reopenProjects") private var reopen = true
    @State private var toolReport = ""
    @State private var testing = false
    var body: some View {
        TabView {
            Form {
                Toggle("Reopen project windows on launch", isOn: $reopen)
                Text("Projects are ordinary local folders. History and recovery copies are stored in Application Support/TeXium.").foregroundStyle(.secondary)
                LabeledContent("Appearance", value: "Follows macOS")
            }.tabItem { Label("General", systemImage: "gearshape") }
            Form {
                TextField("Font family", text: $font)
                Slider(value: $size, in: 10...28, step: 1) { Text("Font size: \(Int(size)) pt") }
                Stepper("Indent width: \(tabWidth)", value: $tabWidth, in: 1...8)
                Toggle("Indent with spaces", isOn: $spaces)
                Toggle("Line numbers", isOn: $lineNumbers)
                Toggle("Highlight current line", isOn: $currentLine)
                Toggle("Syntax highlighting", isOn: $highlighting)
                Toggle("Close braces and brackets", isOn: $autoClose)
                Toggle("LaTeX completion", isOn: $completion)
                Toggle("Check spelling", isOn: $spelling)
            }.tabItem { Label("Editor", systemImage: "text.cursor") }
            Form {
                TextField("TeX binary folder", text: $texPath, prompt: Text("Automatic: /Library/TeX/texbin"))
                Picker("Default engine", selection: $engine) { ForEach(TeXEngine.allCases) { Text($0.title).tag($0.rawValue) } }
                Slider(value: $delay, in: 1...10, step: 0.5) { Text("Automatic compile delay: \(delay, specifier: "%.1f") s") }
                Text("Install MacTeX or BasicTeX with latexmk. Compilation uses only your local tools. Shell escape is disabled by default and configured per project.").foregroundStyle(.secondary)
                Button(testing ? "Testing…" : "Test LaTeX Installation") { testTools() }.disabled(testing)
                if !toolReport.isEmpty { ScrollView { Text(toolReport).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 130) }
            }.tabItem { Label("LaTeX", systemImage: "terminal") }
            Form {
                Toggle("Continuous scrolling", isOn: $continuous)
                Toggle("Show thumbnails by default", isOn: $thumbnails)
                Text("Command-click a PDF location to jump to its source. Use Navigate → Show in PDF for the other direction.").foregroundStyle(.secondary)
            }.tabItem { Label("PDF", systemImage: "doc.richtext") }
        }.formStyle(.grouped).padding(16).frame(width: 570, height: 510)
    }
    private func testTools() {
        testing = true; toolReport = ""
        Task {
            defer { testing = false }
            guard let distribution = TeXDistribution.discover(customPath: texPath) else { toolReport = "No TeX installation found. Install MacTeX/BasicTeX, or select a valid binary directory."; return }
            var lines = ["Detected: " + distribution.directory.path]
            for name in ["latexmk", "pdflatex", "xelatex", "lualatex", "synctex", "texcount", "bibtex", "biber"] {
                guard let tool = distribution.tools[name] else { lines.append("\(name): unavailable"); continue }
                do {
                    let versionArgument = name == "synctex" ? "help" : name == "latexmk" ? "-v" : "--version"
                    let result = try await ProcessRunner().run(executable: tool, arguments: [versionArgument], directory: FileManager.default.temporaryDirectory, environment: distribution.environment)
                    lines.append("\(name): " + (result.output.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? "available"))
                } catch { lines.append("\(name): \(error.localizedDescription)") }
            }
            toolReport = lines.joined(separator: "\n")
        }
    }
}
