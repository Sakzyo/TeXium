import Foundation

public enum TeXEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case pdfLaTeX = "pdflatex", xeLaTeX = "xelatex", luaLaTeX = "lualatex", latex = "latex"
    public var id: String { rawValue }
    public var title: String { switch self { case .pdfLaTeX: "pdfLaTeX"; case .xeLaTeX: "XeLaTeX"; case .luaLaTeX: "LuaLaTeX"; case .latex: "LaTeX → PDF" } }
    public var latexmkFlag: String { switch self { case .pdfLaTeX: "-pdf"; case .xeLaTeX: "-xelatex"; case .luaLaTeX: "-lualatex"; case .latex: "-pdfdvi" } }
}
public enum ShellPolicy: String, CaseIterable, Codable, Sendable {
    case disabled, restricted, enabled
    public var flag: String { switch self { case .disabled: "-no-shell-escape"; case .restricted: "-shell-restricted"; case .enabled: "-shell-escape" } }
}
public struct BuildConfiguration: Codable, Equatable, Sendable {
    public var mainFile: String
    public var engine: TeXEngine
    public var shellPolicy: ShellPolicy
    public var automatic: Bool
    public init(mainFile: String = "main.tex", engine: TeXEngine = .pdfLaTeX, shellPolicy: ShellPolicy = .disabled, automatic: Bool = false) {
        self.mainFile = mainFile; self.engine = engine; self.shellPolicy = shellPolicy; self.automatic = automatic
    }
}
public struct ProjectFile: Identifiable, Hashable, Sendable {
    public var path: String
    public var children: [ProjectFile]?
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var isDirectory: Bool { children != nil }
    public var symbol: String {
        if isDirectory { return "folder" }
        switch (name as NSString).pathExtension.lowercased() {
        case "tex", "sty", "cls": return "doc.text"
        case "bib": return "books.vertical"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "svg", "tiff", "heic": return "photo"
        default: return "doc"
        }
    }
    public init(path: String, children: [ProjectFile]? = nil) { self.path = path; self.children = children }
}
public struct OutlineItem: Identifiable, Equatable, Sendable {
    public var id: String { "\(file):\(offset)" }
    public let title: String
    public let level: Int
    public let file: String
    public let line: Int
    public let offset: Int
}
public enum Severity: String, Codable, Sendable, CaseIterable {
    case error, warning, badBox, information
    public var symbol: String { switch self { case .error: "xmark.octagon.fill"; case .warning: "exclamationmark.triangle.fill"; case .badBox: "rectangle.dashed"; case .information: "info.circle" } }
}
public struct Diagnostic: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var severity: Severity
    public var message: String
    public var file: String?
    public var line: Int?
    public init(severity: Severity, message: String, file: String? = nil, line: Int? = nil) {
        id = UUID(); self.severity = severity; self.message = message; self.file = file; self.line = line
    }
}
public struct BibEntry: Identifiable, Equatable, Sendable {
    public var id: String { "\(file):\(key)" }
    public let key: String
    public let type: String
    public let fields: [String: String]
    public let file: String
    public let line: Int
    public var title: String { fields["title"] ?? key }
    public var author: String { fields["author"] ?? "" }
    public var year: String { fields["year"] ?? fields["date"] ?? "" }
    public var searchText: String { ([key, type] + Array(fields.values)).joined(separator: " ") }
}
public struct SearchHit: Identifiable, Sendable {
    public var id: String { "\(file):\(range.location)" }
    public let file: String
    public let line: Int
    public let excerpt: String
    public let range: NSRange
}
public struct UserNote: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var text: String
    public var file: String?
    public var line: Int?
    public var resolved = false
    public var created = Date()
    public init(text: String, file: String?, line: Int?) { self.text = text; self.file = file; self.line = line }
}
public enum TeXiumError: LocalizedError {
    case message(String), conflict(String), unsafePath(String)
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .conflict(let path): return "\(path) changed on disk. Compare the external version before saving your edits."
        case .unsafePath(let path): return "The path is outside this project or is unsafe: \(path)"
        }
    }
}
