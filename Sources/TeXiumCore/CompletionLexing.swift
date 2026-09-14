import Foundation

struct CompletionContext {
    let kind: CompletionKind
    let command: String
    let range: NSRange
    let query: String
    var excluded: Set<String> = []
}

enum CompletionLexing {
    // Spaces preserve all NSTextView UTF-16 offsets, including emoji and CRLF.
    // Literal environments and inline verbatim must not offer or index LaTeX.
    static func clean(_ source: String) -> String {
        var chars = Array(source.utf16)
        var i = 0
        var literal: String?
        while i < chars.count {
            if let environment = literal {
                let end = Array("\\end{\(environment)}".utf16)
                if chars[i...].starts(with: end) { i += end.count; literal = nil; continue }
                if chars[i] != 10 && chars[i] != 13 { chars[i] = 32 }; i += 1; continue
            }
            if chars[i] == 37 {
                while i < chars.count && chars[i] != 10 && chars[i] != 13 { chars[i] = 32; i += 1 }
                continue
            }
            guard chars[i] == 92 else { i += 1; continue }
            let start = i; i += 1
            guard i < chars.count else { break }
            if !letter(chars[i]) { i += 1; continue } // escaped %, braces, or backslash
            while i < chars.count && letter(chars[i]) { i += 1 }
            let command = String(decoding: chars[(start + 1)..<i], as: UTF16.self)
            if command == "verb" || command == "lstinline" {
                if i < chars.count && chars[i] == 42 { i += 1 }
                guard i < chars.count && chars[i] != 10 && chars[i] != 13 else { continue }
                let delimiter = chars[i]; i += 1
                while i < chars.count && chars[i] != delimiter && chars[i] != 10 && chars[i] != 13 { chars[i] = 32; i += 1 }
                if i < chars.count && chars[i] == delimiter { i += 1 }
            } else if command == "begin" {
                var open = i
                while open < chars.count && [32, 9, 10, 13].contains(chars[open]) { open += 1 }
                if open < chars.count && chars[open] == 123, let close = chars[(open + 1)...].firstIndex(of: 125) {
                    let environment = String(decoding: chars[(open + 1)..<close], as: UTF16.self)
                    if ["verbatim", "verbatim*", "Verbatim", "lstlisting", "minted", "comment"].contains(environment) { literal = environment; i = close + 1 }
                }
            }
        }
        return String(decoding: chars, as: UTF16.self)
    }

    static func context(in source: String, at cursor: Int) -> CompletionContext? {
        let original = source as NSString
        let prefix = original.substring(to: cursor)
        let cleanedPrefix = clean(prefix) as NSString
        // A sentinel is blanked only when the cursor is inside a comment/literal.
        let sentinel = clean(prefix + "X") as NSString
        guard sentinel.character(at: cursor) == 88 else { return nil }
        let ns = clean(source) as NSString
        var start = cursor
        if start > 0 && ns.character(at: start - 1) == 42 { start -= 1 }
        while start > 0 && letter(ns.character(at: start - 1)) { start -= 1 }
        if start > 0 && ns.character(at: start - 1) == 92 {
            var slash = start - 1
            while slash > 0 && ns.character(at: slash - 1) == 92 { slash -= 1 }
            if (start - slash) % 2 == 1 {
                start -= 1; var end = cursor
                while end < ns.length && letter(ns.character(at: end)) { end += 1 }
                if end < ns.length && ns.character(at: end) == 42 { end += 1 }
                return CompletionContext(kind: .command, command: "", range: NSRange(location: start, length: end - start), query: original.substring(with: NSRange(location: start, length: cursor - start)))
            }
        }
        var groups: [(Int, UInt16)] = []; var i = 0
        while i < cleanedPrefix.length {
            let c = cleanedPrefix.character(at: i)
            if c == 92 { i += 2; continue }
            if c == 123 || c == 91 { groups.append((i, c)) }
            if c == 125 || c == 93, groups.last?.1 == (c == 125 ? 123 : 91) { groups.removeLast() }
            i += 1
        }
        guard let group = groups.last else { return nil }
        let before = cleanedPrefix.substring(to: group.0) as NSString
        let commandPattern = try! NSRegularExpression(pattern: #"(?<!\\)\\([A-Za-z]+)\*?\s*(?:\[[^\]]*\]\s*)*$"#)
        guard let match = commandPattern.firstMatch(in: before as String, range: NSRange(location: 0, length: before.length)) else { return nil }
        let command = before.substring(with: match.range(at: 1))
        let kind: CompletionKind
        if group.1 == 91 {
            guard command == "hyperref" else { return nil }; kind = .label
        } else if command.lowercased().contains("cite") { kind = .citation }
        else if ["ref", "eqref", "autoref", "pageref", "nameref", "cref", "Cref", "vref", "Vref", "cpageref", "labelcref"].contains(command) { kind = .label }
        else if ["part", "chapter", "section", "subsection", "subsubsection", "paragraph", "subparagraph"].contains(command) { kind = .heading }
        else if ["begin", "end"].contains(command) { kind = .environment }
        else if ["input", "include", "includegraphics", "bibliography", "addbibresource"].contains(command) { kind = .file }
        else { return nil }
        start = group.0 + 1
        let list = kind == .citation || kind == .label || command == "bibliography"
        if list {
            for position in start..<cursor where ns.character(at: position) == 44 { start = position + 1 }
        }
        while start < cursor && whitespace(ns.character(at: start)) { start += 1 }
        var end = cursor
        while end < ns.length {
            let c = ns.character(at: end)
            if c == 125 || c == 93 || c == 123 || c == 92 || c == 10 || c == 13 || (list && c == 44) { break }
            end += 1
        }
        while end > cursor && whitespace(ns.character(at: end - 1)) { end -= 1 }
        let query = original.substring(with: NSRange(location: start, length: cursor - start)).trimmingCharacters(in: .whitespacesAndNewlines)
        var excluded: Set<String> = []
        if list {
            let previous = ns.substring(with: NSRange(location: group.0 + 1, length: start - group.0 - 1))
            excluded = Set(previous.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        return CompletionContext(kind: kind, command: command, range: NSRange(location: start, length: end - start), query: query, excluded: excluded)
    }

    static func letter(_ c: UInt16) -> Bool { (65...90).contains(c) || (97...122).contains(c) || c == 64 }
    static func whitespace(_ c: UInt16) -> Bool { [32, 9, 10, 13].contains(c) }
}
