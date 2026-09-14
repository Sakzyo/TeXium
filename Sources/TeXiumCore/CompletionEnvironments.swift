import Foundation

enum CompletionEnvironments {
    static func suggestions(context: CompletionContext, source: String, formatting: CompletionFormatting) -> (range: NSRange, items: [CompletionItem]) {
        guard context.command == "begin" else {
            return (context.range, CompletionCatalog.environments.map { CompletionItem($0, detail: "Close LaTeX environment") })
        }
        let ns = source as NSString
        var end = NSMaxRange(context.range)
        while end < ns.length && [32, 9].contains(ns.character(at: end)) { end += 1 }
        let hasBrace = end < ns.length && ns.character(at: end) == 125
        if hasBrace { end += 1 } else { end = NSMaxRange(context.range) }
        let range = NSRange(location: context.range.location, length: end - context.range.location)
        let originalName = ns.substring(with: context.range).trimmingCharacters(in: .whitespacesAndNewlines)
        let existingClosing = hasBrace ? ns.substring(with: NSRange(location: NSMaxRange(context.range), length: end - NSMaxRange(context.range))) : "}"
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: context.range.location, length: 0)))
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let tail = ns.substring(from: end)
        let hasInlineContent = !tail.prefix { $0 != "\r" && $0 != "\n" && $0 != "\r\n" }.trimmingCharacters(in: .whitespaces).isEmpty
        let outer = environmentBalance(in: ns.substring(to: context.range.location)).open
        let closing = environmentBalance(in: tail).closed
        func hasExistingEnd(_ name: String) -> Bool {
            closing.prefix { $0 == name }.count > outer.reversed().prefix { $0 == name }.count
        }
        let items = CompletionCatalog.environments.map { name in
            // Completing an existing opener must not duplicate its body, options,
            // arguments, or matching end. An outer end is safe for a new block.
            if hasInlineContent || hasExistingEnd(name) || hasExistingEnd(originalName) {
                return CompletionItem(name, detail: "LaTeX environment · keep existing contents", insertion: name + existingClosing)
            }
            return CompletionItem.template(name, detail: detail(for: name), source: name + "}" + body(for: name) + "\n\\end{\(name)}",
                                           baseIndent: indent, formatting: formatting, searchText: name)
        }
        return (range, items)
    }

    /// Unmatched boundaries let a new nested list keep the outer list's end.
    /// Balanced nested blocks and commented/literal source do not count.
    private static func environmentBalance(in source: String) -> (open: [String], closed: [String]) {
        let clean = CompletionLexing.clean(source) as NSString
        let expression = try! NSRegularExpression(pattern: #"(?<!\\)\\(begin|end)\s*\{([^{}]+)\}"#)
        var stack: [String] = [], closed: [String] = []
        for match in expression.matches(in: clean as String, range: NSRange(location: 0, length: clean.length)) {
            let name = clean.substring(with: match.range(at: 2))
            if clean.substring(with: match.range(at: 1)) == "begin" { stack.append(name) }
            else if stack.isEmpty { closed.append(name) }
            else if stack.last == name { stack.removeLast() }
        }
        return (stack, closed)
    }

    private static func detail(for name: String) -> String {
        switch name {
        case "figure", "figure*": return "Image, caption, and label · graphicx package"
        case "table", "table*": return "Two-column table, caption, and label"
        case "itemize", "enumerate": return "List with a first item"
        case "description": return "Description list with a term and item"
        case "frame": return "Frame title and body · beamer class"
        case "tabularx": return "Flexible-width table · tabularx package"
        default: return "Complete environment · Tab through fields"
        }
    }

    private static func body(for name: String) -> String {
        switch name {
        case "figure", "figure*":
            return #"""

                \centering
                \includegraphics[width=0.5\linewidth]{«»}
                \caption{«Caption»}
                \label{«fig:placeholder»}
            """#
        case "itemize", "enumerate": return "\n    \\item «»"
        case "description": return "\n    \\item[«»] «»"
        case "table", "table*":
            return #"""
            [«htbp»]
                \centering
                \begin{tabular}{«c|c»}
                    «» & «» \\
                    «» & «»
                \end{tabular}
                \caption{«Caption»}
                \label{«tab:placeholder»}
            """#
        case "tabular", "array":
            return "{«\(name == "array" ? "cc" : "c|c")»}" + #"""

                «» & «» \\
                «» & «»
            """#
        case "tabularx":
            return #"""
            {«\linewidth»}{«XX»}
                «» & «» \\
                «» & «»
            """#
        case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "cases":
            return #"""

                «» & «» \\
                «» & «»
            """#
        case "frame": return "{«Frame Title»}\n    «»"
        case "minipage": return "{«0.5\\linewidth»}\n    «»"
        case "document": return "\n«»"
        default: return "\n    «»"
        }
    }
}
