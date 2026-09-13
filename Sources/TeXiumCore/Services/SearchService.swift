import Foundation

public struct SearchOptions: Sendable {
    public var regex = false
    public var caseSensitive = false
    public var wholeWord = false
    public init(regex: Bool = false, caseSensitive: Bool = false, wholeWord: Bool = false) { self.regex = regex; self.caseSensitive = caseSensitive; self.wholeWord = wholeWord }
    public func expression(_ query: String) throws -> NSRegularExpression {
        var pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = "\\b(?:" + pattern + ")\\b" }
        return try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }
}
public struct SearchDocument: Sendable {
    public let file: String
    public let baseline: TextFile
    public let matches: [NSRange]
}
public struct SearchResult: Sendable {
    public let hits: [SearchHit]
    public let documents: [SearchDocument]
    public init(hits: [SearchHit], documents: [SearchDocument]) { self.hits = hits; self.documents = documents }
}
public enum SearchService {
    public static func search(root: URL, query: String, options: SearchOptions) throws -> SearchResult {
        guard !query.isEmpty else { return SearchResult(hits: [], documents: []) }
        let expression = try options.expression(query)
        var hits: [SearchHit] = []; var documents: [SearchDocument] = []
        for node in ProjectFileSystem.flatten(try ProjectFileSystem.tree(at: root)) where !node.isDirectory && ProjectFileSystem.textExtensions.contains((node.path as NSString).pathExtension.lowercased()) {
            try Task.checkCancellation()
            let file = try ProjectFileSystem.read(ProjectFileSystem.resolve(node.path, in: root)); let text = file.text as NSString
            let matches = expression.matches(in: file.text, range: NSRange(location: 0, length: text.length)).map(\.range)
            if matches.isEmpty { continue }
            documents.append(SearchDocument(file: node.path, baseline: file, matches: matches))
            hits += matches.map { range in
                SearchHit(file: node.path, line: LaTeXParser.lineNumber(at: range.location, in: file.text), excerpt: text.substring(with: text.lineRange(for: range)).trimmingCharacters(in: .newlines), range: range)
            }
        }
        return SearchResult(hits: hits, documents: documents)
    }
    public static func replace(root: URL, result: SearchResult, query: String, replacement: String, options: SearchOptions) throws {
        let expression = try options.expression(query)
        for doc in result.documents {
            let url = try ProjectFileSystem.resolve(doc.file, in: root)
            guard try Data(contentsOf: url) == doc.baseline.baseline else { throw TeXiumError.conflict(doc.file) }
        }
        for doc in result.documents {
            let template = options.regex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
            let text = expression.stringByReplacingMatches(in: doc.baseline.text, range: NSRange(location: 0, length: (doc.baseline.text as NSString).length), withTemplate: template)
            _ = try ProjectFileSystem.save(text, file: doc.baseline, to: ProjectFileSystem.resolve(doc.file, in: root))
        }
    }
}
