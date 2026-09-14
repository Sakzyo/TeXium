import Foundation

public struct CompletionFormatting: Sendable {
    public let indentation: String
    public let lineEnding: String
    public init(indentation: String = "    ", lineEnding: String = "\n") {
        self.indentation = indentation; self.lineEnding = lineEnding
    }
    static func inferred(from source: String) -> Self {
        let newline = source.firstIndex { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }.map { String(source[$0]) } ?? "\n"
        return Self(lineEnding: newline)
    }
}

extension CompletionItem {
    /// Catalog-only notation: «default» is a selected field; «» is an empty one.
    /// Four leading spaces represent one editor indentation level.
    static func template(_ title: String, detail: String, source: String, baseIndent: String = "",
                         formatting: CompletionFormatting = .init(), searchText: String? = nil) -> Self {
        let lines = source.components(separatedBy: "\n").enumerated().map { index, line in
            let spaces = line.prefix { $0 == " " }.count
            return (index == 0 ? "" : baseIndent) + String(repeating: formatting.indentation, count: spaces / 4) + line.dropFirst(spaces)
        }.joined(separator: formatting.lineEnding) as NSString
        let expression = try! NSRegularExpression(pattern: "«([^»]*)»")
        var insertion = "", fields: [NSRange] = [], offset = 0
        for match in expression.matches(in: lines as String, range: NSRange(location: 0, length: lines.length)) {
            insertion += lines.substring(with: NSRange(location: offset, length: match.range.location - offset))
            let value = lines.substring(with: match.range(at: 1))
            fields.append(NSRange(location: (insertion as NSString).length, length: (value as NSString).length))
            insertion += value; offset = NSMaxRange(match.range)
        }
        insertion += lines.substring(from: offset)
        fields.append(NSRange(location: (insertion as NSString).length, length: 0))
        return Self(title, detail: detail, insertion: insertion, fields: fields, searchText: searchText)
    }
}

/// Tracks native text selections as fields grow or shrink. Edits outside the
/// active field cancel navigation instead of moving stale offsets into code.
public struct CompletionSnippetSession {
    public private(set) var fields: [NSRange]
    public private(set) var activeIndex = 0
    public var selection: NSRange { fields[activeIndex] }
    public var isAtEnd: Bool { activeIndex == fields.count - 1 }

    public init?(fields: [NSRange], base: Int) {
        guard !fields.isEmpty else { return nil }
        self.fields = fields.map { NSRange(location: base + $0.location, length: $0.length) }
    }
    public mutating func trackSelection(_ range: NSRange) -> Bool {
        func contains(_ field: NSRange) -> Bool { range.location >= field.location && NSMaxRange(range) <= NSMaxRange(field) }
        if contains(selection) { return true }
        guard let index = fields.firstIndex(where: contains) else { return false }
        activeIndex = index; return true
    }
    public mutating func replace(_ range: NSRange, with text: String) -> Bool {
        guard range.location >= selection.location, NSMaxRange(range) <= NSMaxRange(selection) else { return false }
        let delta = (text as NSString).length - range.length
        fields[activeIndex].length += delta
        for index in fields.indices where index > activeIndex { fields[index].location += delta }
        return true
    }
    public mutating func advance(backwards: Bool) -> NSRange? {
        let next = activeIndex + (backwards ? -1 : 1)
        guard fields.indices.contains(next) else { return nil }
        activeIndex = next; return selection
    }
}
