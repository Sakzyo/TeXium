import SwiftUI
import TeXiumCore

struct EquationAssistant: View {
    @Bindable var session: ProjectSession
    @State private var environment = "equation"
    @State private var equation = "e^{i\\pi} + 1 = 0"
    @State private var label = ""
    private let environments = ["Inline", "Display", "equation", "align", "gather", "cases", "pmatrix", "bmatrix"]
    private var source: String {
        if environment == "Inline" { return "$\(equation)$" }
        if environment == "Display" { return "\\[\n\(equation)\n\\]" }
        let body = "\\begin{\(environment)}\n\(equation)" + (label.isEmpty || ["cases", "pmatrix", "bmatrix"].contains(environment) ? "" : "\n\\label{\(label)}") + "\n\\end{\(environment)}"
        return ["cases", "pmatrix", "bmatrix"].contains(environment) ? "\\[\n\(body)\n\\]" : body
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert an Equation").font(.title2.weight(.semibold))
            Picker("Environment", selection: $environment) { ForEach(environments, id: \.self) { Text($0).tag($0) } }
            TextEditor(text: $equation).font(.system(.body, design: .monospaced)).frame(height: 130)
            TextField("Label (optional)", text: $label)
            Text("LaTeX preview").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            NativeTextDisplay(text: source).frame(height: 140)
            Text("align, gather, cases, and matrices require amsmath. Compile the project to see the rendered result.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { session.sheet = nil }; Button("Insert Equation") { session.insert(source); session.sheet = nil }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 620)
        .onChange(of: environment) { _, value in
            if value == "cases" { equation = "x^2 & x \\geq 0 \\\\\n-x & x < 0" }
            if value == "pmatrix" || value == "bmatrix" { equation = "a & b \\\\\nc & d" }
            if value == "align" { equation = "a &= b + c \\\\\n  &= d" }
        }
    }
}

struct FigureAssistant: View {
    @Bindable var session: ProjectSession
    @State private var path = ""
    @State private var width = 0.8
    @State private var placement = "htbp"
    @State private var caption = ""
    @State private var label = "fig:"
    private var images: [ProjectFile] { session.files.filter { ["png", "jpg", "jpeg", "pdf", "tiff", "eps"].contains(($0.path as NSString).pathExtension.lowercased()) } }
    private var source: String { "\\begin{figure}[\(placement)]\n  \\centering\n  \\includegraphics[width=\(String(format: "%.2f", width))\\linewidth]{\\detokenize{\(path)}}\n  \\caption{\(caption)}\n  \\label{\(label)}\n\\end{figure}\n" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert a Figure").font(.title2.weight(.semibold))
            HStack { Picker("Image", selection: $path) { Text("Choose an image").tag(""); ForEach(images) { Text($0.path).tag($0.path) } }; Button("Import…") { session.importFiles() } }
            if !path.isEmpty { AssetPreview(url: session.root.appendingPathComponent(path)).frame(height: 130) }
            Slider(value: $width, in: 0.1...1, step: 0.05) { Text("Width: \(Int(width * 100))%") }
            Picker("Placement", selection: $placement) { Text("Here, top, bottom, page").tag("htbp"); Text("Top").tag("t"); Text("Bottom").tag("b"); Text("Float page").tag("p") }
            TextField("Caption (LaTeX)", text: $caption)
            TextField("Label", text: $label)
            Text("Requires graphicx. Figure paths are relative to the project root.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { session.sheet = nil }; Button("Insert Figure") { session.insert(source); session.sheet = nil }.keyboardShortcut(.defaultAction).disabled(path.isEmpty || path.contains("{") || path.contains("}") || path.contains("%")) }
        }.padding(24).frame(width: 600).onAppear { path = images.first?.path ?? "" }
    }
}

struct TableAssistant: View {
    @Bindable var session: ProjectSession
    @State private var rows = 3
    @State private var columns = 3
    @State private var cells = Array(repeating: Array(repeating: "", count: 12), count: 12)
    @State private var alignment = "l"
    @State private var borders = true
    @State private var caption = ""
    @State private var label = "tab:"
    @State private var merge = 1
    @State private var placement = "htbp"
    private var source: String {
        let separator = borders ? "|" : ""
        let spec = separator + Array(repeating: alignment, count: columns).joined(separator: separator) + separator
        var lines = ["\\begin{table}[\(placement)]", "  \\centering", "  \\begin{tabular}{\(spec)}"]
        if borders { lines.append("    \\hline") }
        for row in 0..<rows {
            var entries = Array(cells[row].prefix(columns))
            if row == 0 && merge > 1 { entries = ["\\multicolumn{\(min(merge, columns))}{\(separator)\(alignment)\(separator)}{\(cells[0][0])}"] + Array(entries.dropFirst(min(merge, columns))) }
            lines.append("    " + entries.joined(separator: " & ") + " \\\\" + (borders ? " \\hline" : ""))
        }
        lines += ["  \\end{tabular}", "  \\caption{\(caption)}", "  \\label{\(label)}", "\\end{table}"]
        return lines.joined(separator: "\n") + "\n"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert a Table").font(.title2.weight(.semibold))
            HStack { Stepper("Rows: \(rows)", value: $rows, in: 1...12); Stepper("Columns: \(columns)", value: $columns, in: 1...12); Picker("Alignment", selection: $alignment) { Text("Left").tag("l"); Text("Center").tag("c"); Text("Right").tag("r") }; Toggle("Borders", isOn: $borders) }
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow { ForEach(0..<columns, id: \.self) { column in TextField("\(row + 1),\(column + 1)", text: $cells[row][column]).textFieldStyle(.roundedBorder).frame(width: 115).disabled(row == 0 && column > 0 && column < merge) } }
                    }
                }.padding(3)
            }.frame(height: 160)
            HStack { Stepper("Merge first-row cells: \(merge)", value: $merge, in: 1...columns); Picker("Placement", selection: $placement) { Text("Automatic").tag("htbp"); Text("Top").tag("t"); Text("Bottom").tag("b") } }
            TextField("Caption (LaTeX)", text: $caption); TextField("Label", text: $label)
            NativeTextDisplay(text: source).frame(height: 150)
            HStack { Text("Cell contents accept LaTeX.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Cancel") { session.sheet = nil }; Button("Insert Table") { session.insert(source); session.sheet = nil }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 760).onChange(of: columns) { _, value in merge = min(merge, value) }
    }
}
