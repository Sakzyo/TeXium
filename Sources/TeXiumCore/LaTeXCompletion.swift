import Foundation

public enum CompletionKind: String, Sendable {
    case command, label, citation, heading, environment, file
    public var title: String {
        switch self {
        case .command: return "LaTeX commands"
        case .label: return "Project labels"
        case .citation: return "Project bibliography"
        case .heading: return "Section headings"
        case .environment: return "Environments"
        case .file: return "Project files"
        }
    }
}

public struct CompletionItem: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let insertion: String
    /// UTF-16 ranges of editable fields, followed by the final insertion point.
    public let fields: [NSRange]
    public var stops: [Int] { fields.map(\.location) }
    let searchText: String

    init(_ title: String, detail: String, insertion: String? = nil, stops: [Int] = [], fields: [NSRange]? = nil, searchText: String? = nil) {
        self.title = title; self.detail = detail; self.insertion = insertion ?? title
        self.fields = fields ?? stops.map { NSRange(location: $0, length: 0) }
        self.searchText = searchText ?? title + " " + detail
    }

    static func command(_ name: String, arguments: [String] = [], detail: String) -> Self {
        let command = "\\" + name
        let start = (command as NSString).length
        return Self(command + arguments.map { "{" + $0 + "}" }.joined(), detail: detail,
                    insertion: command + String(repeating: "{}", count: arguments.count),
                    stops: arguments.indices.map { start + $0 * 2 + 1 } + (arguments.isEmpty ? [] : [start + arguments.count * 2]),
                    searchText: command)
    }
}

public struct CompletionResult: Sendable {
    public let kind: CompletionKind
    public let range: NSRange
    public let query: String
    public let items: [CompletionItem]
}

/// A per-file index, refreshed off the main actor. Live buffers replace their
/// disk entries, so deleted/renamed unsaved keys cannot survive as stale choices.
public struct CompletionProject: Sendable {
    var documents: [String: CompletionDocument] = [:]
    public init() {}
    public mutating func update(_ source: String, file: String) {
        guard documents[file]?.source != source else { return }
        documents[file] = CompletionDocument(source: source, file: file)
    }
}

struct CompletionDocument: Sendable {
    let source: String
    var labels: [CompletionItem] = []
    var citations: [CompletionItem] = []
    var headings: [CompletionItem] = []
    var commands: [CompletionItem] = []

    init(source: String, file: String) {
        self.source = source
        if (file as NSString).pathExtension.lowercased() == "bib" {
            citations = BibTeXParser.parse(source, file: file).map {
                CompletionItem($0.key, detail: [$0.title, $0.author, $0.year, file].filter { !$0.isEmpty }.joined(separator: " · "), searchText: $0.searchText)
            }
            return
        }
        let clean = CompletionLexing.clean(source) as NSString
        let outline = LaTeXParser.outline(clean as String, file: file)
        headings = outline.map { CompletionItem($0.title, detail: "\(file):\($0.line)") }
        let labelExpression = try! NSRegularExpression(pattern: #"(?<!\\)\\label\s*\{([^{}]+)\}"#)
        labels = labelExpression.matches(in: clean as String, range: NSRange(location: 0, length: clean.length)).compactMap { match in
            let key = clean.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            let heading = outline.last { $0.offset < match.range.location }?.title
            let location = "\(file):\(LaTeXParser.lineNumber(at: match.range.location, in: source))"
            return CompletionItem(key, detail: [heading, location].compactMap { $0 }.joined(separator: " · "))
        }
        let definition = try! NSRegularExpression(pattern: #"\\(?:newcommand|renewcommand|providecommand|DeclareRobustCommand)\*?\s*(?:\{\s*)?\\([A-Za-z@]+)\s*\}?\s*(?:\[(\d)\])?\s*(\[[^\]]*\])?"#)
        commands = definition.matches(in: clean as String, range: NSRange(location: 0, length: clean.length)).map { match in
            let count = match.range(at: 2).location == NSNotFound ? 0 : Int(clean.substring(with: match.range(at: 2))) ?? 0
            let required = max(0, count - (match.range(at: 3).location == NSNotFound ? 0 : 1))
            return .command(clean.substring(with: match.range(at: 1)), arguments: (0..<required).map { "argument \($0 + 1)" }, detail: "Defined in " + file)
        }
    }
}

public enum LaTeXCompletion {
    public static func suggestions(in source: String, at cursor: Int, file: String, project: CompletionProject,
                                   liveBuffers: [String: String] = [:], files: [String] = [], explicit: Bool = false,
                                   formatting: CompletionFormatting? = nil) -> CompletionResult? {
        let ns = source as NSString
        guard cursor >= 0, cursor <= ns.length else { return nil }
        var context = CompletionLexing.context(in: source, at: cursor)
        // Also complete an opener after the user types/skips its closing brace.
        if context == nil, cursor > 0, ns.character(at: cursor - 1) == 125,
           let opener = CompletionLexing.context(in: source, at: cursor - 1), opener.kind == .environment, opener.command == "begin" {
            context = opener
        }
        guard let context else { return nil }
        var replacementRange = context.range
        var project = project
        for (path, text) in liveBuffers { project.update(text, file: path) }
        project.update(source, file: file)
        let documents = project.documents.keys.sorted { lhs, rhs in
            if (lhs == file) != (rhs == file) { return lhs == file }; return lhs < rhs
        }.compactMap { project.documents[$0] }
        var candidates: [CompletionItem]
        switch context.kind {
        case .command:
            candidates = documents.flatMap(\.commands) + CompletionCatalog.commands
            // Retain existing arguments when completing in the middle of code.
            let suffix = (source as NSString).substring(from: NSMaxRange(context.range)).drop(while: { $0.isWhitespace })
            if suffix.first == "{" || suffix.first == "[" {
                candidates = candidates.map { item in
                    let name = String(item.insertion.prefix { $0 != "{" && $0 != "[" })
                    return CompletionItem(item.title, detail: item.detail, insertion: name, searchText: item.searchText)
                }
            }
        case .citation: candidates = documents.flatMap(\.citations)
        case .label: candidates = documents.flatMap(\.labels)
        case .heading:
            guard explicit || !context.query.isEmpty else { return nil }
            let currentTitle = (source as NSString).substring(with: context.range)
            candidates = documents.flatMap(\.headings).filter { $0.insertion != currentTitle }
        case .environment:
            let completion = CompletionEnvironments.suggestions(context: context, source: source, formatting: formatting ?? .inferred(from: source))
            replacementRange = completion.range; candidates = completion.items
        case .file:
            candidates = files.filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                switch context.command {
                case "includegraphics": return ["pdf", "png", "jpg", "jpeg", "eps", "svg"].contains(ext)
                case "bibliography", "addbibresource": return ext == "bib"
                default: return ext == "tex"
                }
            }.map { path in
                let insertion = ["include", "bibliography"].contains(context.command) ? (path as NSString).deletingPathExtension : path
                return CompletionItem(insertion, detail: "Project file")
            }
        }
        var seen = Set<String>()
        let query = context.query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let ranked = candidates.compactMap { item -> (CompletionItem, Int)? in
            let identity = context.kind == .command ? item.searchText : item.insertion
            guard seen.insert(identity).inserted, !context.excluded.contains(item.insertion) else { return nil }
            let key = (context.kind == .environment ? item.title : item.insertion).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let search = item.searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if key.hasPrefix(query) { return (item, key == query ? 0 : 1) }
            guard context.kind != .command, terms.allSatisfy({ search.contains($0) }) else { return nil }
            return (item, key.contains(query) ? 2 : 3)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending
        }
        guard !ranked.isEmpty else { return nil }
        return CompletionResult(kind: context.kind, range: replacementRange, query: context.query, items: Array(ranked.prefix(100).map(\.0)))
    }
}
