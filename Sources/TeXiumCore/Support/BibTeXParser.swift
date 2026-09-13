import Foundation

public enum BibTeXParser {
    public static func parse(_ source: String, file: String = "references.bib") -> [BibEntry] {
        let s = source as NSString; var i = 0; var entries: [BibEntry] = []
        func skipSpace() {
            while i < s.length {
                let c = s.character(at: i)
                if c == 37 { while i < s.length && s.character(at: i) != 10 { i += 1 } }
                else if c == 32 || c == 9 || c == 10 || c == 13 || c == 44 { i += 1 }
                else { break }
            }
        }
        func word() -> String {
            let start = i
            while i < s.length && ![UInt16(32), 9, 10, 13, 44, 61, 123, 125, 40, 41].contains(s.character(at: i)) { i += 1 }
            return s.substring(with: NSRange(location: start, length: i - start))
        }
        func value(closing: UInt16) -> String {
            skipSpace(); guard i < s.length else { return "" }
            let first = s.character(at: i)
            if first == 123 || first == 34 {
                i += 1; let start = i; var depth = first == 123 ? 1 : 0; var escaped = false
                while i < s.length {
                    let c = s.character(at: i)
                    if !escaped {
                        if c == 123 { depth += 1 }
                        if c == 125 { depth -= 1 }
                        if (first == 123 && depth == 0) || (first == 34 && c == 34 && depth == 0) {
                            let result = s.substring(with: NSRange(location: start, length: i - start)); i += 1; return result
                        }
                    }
                    escaped = c == 92 && !escaped; i += 1
                }
                return s.substring(from: start)
            }
            let start = i
            while i < s.length && s.character(at: i) != 44 && s.character(at: i) != closing && s.character(at: i) != 35 { i += 1 }
            return s.substring(with: NSRange(location: start, length: i - start)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while i < s.length {
            skipSpace(); guard i < s.length else { break }
            guard s.character(at: i) == 64 else { i += 1; continue }
            let start = i; i += 1; let type = word().lowercased(); skipSpace()
            guard i < s.length && (s.character(at: i) == 123 || s.character(at: i) == 40) else { continue }
            let closing: UInt16 = s.character(at: i) == 123 ? 125 : 41
            i += 1; skipSpace(); let key = word(); var fields: [String: String] = [:]
            while i < s.length && s.character(at: i) != closing {
                skipSpace(); if i >= s.length || s.character(at: i) == closing { break }
                let before = i; let field = word().lowercased(); skipSpace()
                if i < s.length && s.character(at: i) == 61 {
                    i += 1; var content = value(closing: closing)
                    while i < s.length {
                        while i < s.length && [UInt16(32), 9, 10, 13].contains(s.character(at: i)) { i += 1 }
                        guard i < s.length && s.character(at: i) == 35 else { break }
                        i += 1; content += value(closing: closing)
                    }
                    fields[field] = content
                }
                if i == before { i += 1 }
            }
            if i < s.length { i += 1 }
            if !["comment", "preamble", "string"].contains(type), !key.isEmpty {
                entries.append(BibEntry(key: key, type: type, fields: fields, file: file, line: LaTeXParser.lineNumber(at: start, in: source)))
            }
        }
        return entries
    }
}
