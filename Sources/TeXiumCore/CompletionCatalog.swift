import Foundation

enum CompletionCatalog {
    static let environments = ["document", "equation", "equation*", "align", "align*", "aligned", "gather", "gather*", "multline", "multline*", "split", "array", "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "cases", "itemize", "enumerate", "description", "figure", "figure*", "table", "table*", "tabular", "tabularx", "abstract", "center", "verbatim", "frame", "theorem", "lemma", "proof", "quote", "quotation", "minipage"]
    static let commands: [CompletionItem] = {
        var result: [CompletionItem] = []
        func add(_ names: [String], _ arguments: [String], _ detail: String) {
            result += names.map { .command($0, arguments: arguments, detail: detail) }
        }
        add(["part", "chapter", "section", "subsection", "subsubsection", "paragraph", "subparagraph"], ["title"], "Section heading")
        add(["part*", "chapter*", "section*", "subsection*", "subsubsection*", "paragraph*", "subparagraph*"], ["title"], "Unnumbered heading")
        add(["ref", "eqref", "autoref", "pageref", "nameref", "cref", "Cref", "vref", "cpageref", "labelcref"], ["label"], "Reference a project label")
        add(["cite", "citep", "citet", "citeauthor", "citeyear", "parencite", "textcite", "autocite", "footcite", "fullcite", "nocite"], ["key"], "Cite from the project bibliography")
        add(["label"], ["key"], "Define a cross-reference label")
        add(["textbf", "textit", "texttt", "textsf", "textrm", "textsc", "emph", "underline", "mbox"], ["text"], "Text formatting")
        add(["caption", "footnote", "title", "author", "date", "thanks"], ["text"], "Document text")
        result.append(.template(#"\documentclass[options]{class}"#, detail: "Document class and options", source: #"\documentclass[«»]{«article»}"#, searchText: #"\documentclass"#))
        for name in ["usepackage", "RequirePackage"] {
            result.append(.template("\\\(name)[options]{package}", detail: "Load a LaTeX package with options", source: "\\\(name)[«»]{«»}", searchText: "\\" + name))
        }
        add(["begin", "end"], ["environment"], "LaTeX environment")
        add(["input", "include"], ["file"], "Insert a project file")
        result.append(.template(#"\includegraphics[width]{file}"#, detail: "Image with editable width · graphicx package", source: #"\includegraphics[width=«0.5\linewidth»]{«»}"#, searchText: #"\includegraphics"#))
        add(["bibliography", "addbibresource"], ["file"], "Project bibliography file")
        add(["bibliographystyle"], ["style"], "BibTeX style")
        add(["frac", "dfrac", "tfrac", "binom"], ["numerator", "denominator"], "Math fraction or binomial")
        add(["sqrt", "overline", "hat", "bar", "vec", "mathrm", "mathbf", "mathbb", "mathcal", "mathsf", "operatorname", "text"], ["expression"], "Math expression")
        add(["href"], ["url", "text"], "Hyperlink")
        add(["url"], ["url"], "Web address")
        add(["newcommand", "renewcommand", "providecommand"], ["command", "definition"], "Define a custom command")
        add(["newenvironment"], ["name", "begin", "end"], "Define an environment")
        add(["multicolumn"], ["columns", "alignment", "text"], "Span table columns")
        add(["item", "tableofcontents", "listoffigures", "listoftables", "maketitle", "printbibliography", "appendix", "newpage", "clearpage", "pagebreak", "noindent", "par", "centering", "hline", "toprule", "midrule", "bottomrule", "hfill", "vfill"], [], "LaTeX command")
        add(["alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Phi", "Psi", "Omega"], [], "Greek letter")
        add(["sum", "prod", "int", "iint", "oint", "lim", "log", "ln", "exp", "sin", "cos", "tan", "min", "max", "sup", "inf", "infty", "partial", "nabla", "forall", "exists", "in", "notin", "subset", "subseteq", "cup", "cap", "times", "cdot", "pm", "mp", "leq", "geq", "neq", "approx", "equiv", "to", "rightarrow", "leftarrow", "Rightarrow", "Leftrightarrow", "left", "right", "ldots", "cdots"], [], "Math symbol or operator")
        return result
    }()
}
