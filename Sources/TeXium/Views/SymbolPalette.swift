import SwiftUI

struct MathSymbol: Identifiable {
    let glyph: String
    let command: String
    let category: String
    var id: String { command }
    var package: String? { ["\\mathbb{R}", "\\mathbb{N}", "\\mathbb{Z}", "\\varnothing"].contains(command) ? "amssymb" : nil }
    static let all: [MathSymbol] = {
        let groups: [(String, [(String, String)])] = [
            ("Greek", [("α","alpha"),("β","beta"),("γ","gamma"),("δ","delta"),("ε","epsilon"),("ζ","zeta"),("η","eta"),("θ","theta"),("ι","iota"),("κ","kappa"),("λ","lambda"),("μ","mu"),("ν","nu"),("ξ","xi"),("π","pi"),("ρ","rho"),("σ","sigma"),("τ","tau"),("υ","upsilon"),("φ","phi"),("χ","chi"),("ψ","psi"),("ω","omega"),("Γ","Gamma"),("Δ","Delta"),("Θ","Theta"),("Λ","Lambda"),("Ξ","Xi"),("Π","Pi"),("Σ","Sigma"),("Φ","Phi"),("Ψ","Psi"),("Ω","Omega")]),
            ("Arithmetic", [("±","pm"),("∓","mp"),("×","times"),("÷","div"),("·","cdot"),("√","sqrt{}")]),
            ("Relations", [("≤","leq"),("≥","geq"),("≠","neq"),("≈","approx"),("≡","equiv"),("∼","sim"),("∝","propto"),("≪","ll"),("≫","gg")]),
            ("Arrows", [("→","rightarrow"),("←","leftarrow"),("↔","leftrightarrow"),("⇒","Rightarrow"),("⇐","Leftarrow"),("⇔","Leftrightarrow"),("↦","mapsto"),("↑","uparrow"),("↓","downarrow")]),
            ("Sets", [("∈","in"),("∉","notin"),("⊂","subset"),("⊆","subseteq"),("⊃","supset"),("∪","cup"),("∩","cap"),("∅","varnothing"),("ℝ","mathbb{R}"),("ℕ","mathbb{N}"),("ℤ","mathbb{Z}")]),
            ("Calculus", [("∫","int"),("∮","oint"),("∂","partial"),("∇","nabla"),("∞","infty"),("∑","sum"),("∏","prod"),("lim","lim")]),
            ("Logic", [("∀","forall"),("∃","exists"),("¬","neg"),("∧","land"),("∨","lor"),("⊢","vdash"),("⊨","models"),("⊥","perp")]),
            ("Delimiters", [("⟨","langle"),("⟩","rangle"),("⌊","lfloor"),("⌋","rfloor"),("⌈","lceil"),("⌉","rceil"),("‖","Vert")]),
            ("Operators", [("sin","sin"),("cos","cos"),("tan","tan"),("log","log"),("ln","ln"),("exp","exp"),("det","det"),("max","max"),("min","min")]),
            ("Miscellaneous", [("…","ldots"),("⋯","cdots"),("⋮","vdots"),("⋱","ddots"),("ℏ","hbar"),("ℓ","ell"),("ℜ","Re"),("ℑ","Im")])
        ]
        return groups.flatMap { category, pairs in pairs.map { MathSymbol(glyph: $0.0, command: "\\" + $0.1, category: category) } }
    }()
}
struct SymbolPalette: View {
    @Bindable var session: ProjectSession
    @State private var query = ""
    @State private var category = "All"
    @State private var selected: String?
    @AppStorage("favoriteSymbols") private var favorites = ""
    @AppStorage("recentSymbols") private var recent = ""
    private var symbols: [MathSymbol] {
        MathSymbol.all.filter {
            (category == "All" || $0.category == category || (category == "Favorites" && favorites.components(separatedBy: "|").contains($0.command)) || (category == "Recent" && recent.components(separatedBy: "|").contains($0.command))) && (query.isEmpty || $0.command.localizedCaseInsensitiveContains(query) || $0.glyph.contains(query))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mathematical Symbols").font(.title2.weight(.semibold))
            HStack {
                TextField("Search symbols or commands", text: $query)
                Picker("Category", selection: $category) { ForEach(["All", "Favorites", "Recent"] + Array(Set(MathSymbol.all.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) } }.frame(width: 200)
            }
            List(symbols, selection: $selected) { symbol in
                HStack(spacing: 16) {
                    Text(symbol.glyph).font(.system(size: 24, design: .serif)).frame(width: 42)
                    Text(symbol.command).font(.system(.body, design: .monospaced))
                    Spacer()
                    if let package = symbol.package { Text(package).font(.caption).foregroundStyle(.secondary) }
                    Text(symbol.category).font(.caption).foregroundStyle(.tertiary)
                }.tag(symbol.command).onTapGesture(count: 2) { insert(symbol.command) }
                .contextMenu { Button(favorites.components(separatedBy: "|").contains(symbol.command) ? "Remove Favorite" : "Favorite") { toggleFavorite(symbol.command) } }
            }.listStyle(.inset)
            HStack {
                Text("Insert in a math environment. Right-click to favorite.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { session.sheet = nil }; Button("Insert") { if let selected { insert(selected) } }.disabled(selected == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 680, height: 560)
    }
    private func insert(_ command: String) { var values = recent.components(separatedBy: "|").filter { $0 != command && !$0.isEmpty }; values.insert(command, at: 0); recent = values.prefix(24).joined(separator: "|"); session.insert(command + " "); session.sheet = nil }
    private func toggleFavorite(_ command: String) { var values = Set(favorites.components(separatedBy: "|").filter { !$0.isEmpty }); if values.contains(command) { values.remove(command) } else { values.insert(command) }; favorites = values.sorted().joined(separator: "|") }
}
