import SwiftUI
import TeXiumCore

struct SyntaxColorSettings: View {
    @AppStorage(SyntaxPalette.defaultsKey) private var savedColors = Data()
    @AppStorage("highlighting") private var highlighting = true
    private var palette: SyntaxPalette { SyntaxPalette(data: savedColors) }

    var body: some View {
        Form {
            Section {
                Toggle("Syntax highlighting", isOn: $highlighting)
                Text("Colors apply to all projects. Examples and open editors update immediately.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ForEach(SyntaxCategory.allCases, id: \.self) { category in
                    HStack {
                        SyntaxColorControl(category: category, color: binding(for: category))
                        Button("Reset \(category.title) Color", systemImage: "arrow.counterclockwise") {
                            var updated = palette
                            updated.reset(category)
                            savedColors = updated.data
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Use the default color")
                        .disabled(!palette.isCustomized(category))
                    }
                }
            }
            Section {
                Button("Restore Default Colors") { savedColors = Data() }
                    .disabled(!palette.hasCustomColors)
                Text("Default colors follow macOS appearance. Custom colors use the same shade in Light and Dark mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for category: SyntaxCategory) -> Binding<Color> {
        Binding(get: { Color(nsColor: palette.color(for: category)) }, set: { color in
            var updated = palette
            updated.setColor(NSColor(color), for: category)
            savedColors = updated.data
        })
    }
}

private struct SyntaxColorControl: View {
    let category: SyntaxCategory
    @Binding var color: Color
    @State private var hex = ""
    @FocusState private var editingHex: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            ColorPicker(selection: $color, supportsOpacity: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                    Text(category.example).font(.system(.caption, design: .monospaced)).foregroundStyle(color)
                }
            }
            .accessibilityLabel(category.title + " color")
            .accessibilityIdentifier("syntax-color-" + category.rawValue)
            TextField("#RRGGBB", text: $hex)
                .labelsHidden()
                .font(.system(.caption, design: .monospaced)).textFieldStyle(.roundedBorder).frame(width: 82)
                .accessibilityLabel(category.title + " hex color")
                .accessibilityIdentifier("syntax-hex-" + category.rawValue)
                .help("Enter a six-digit hex color, such as #FF8800")
                .focused($editingHex)
                .onChange(of: hex) { _, value in
                    if let chosen = SyntaxPalette.color(fromHex: value), SyntaxPalette.hex(for: NSColor(color)) != SyntaxPalette.hex(for: chosen) {
                        color = Color(nsColor: chosen)
                    }
                }
                .onSubmit {
                    if let chosen = SyntaxPalette.color(fromHex: hex) { color = Color(nsColor: chosen) }
                    refreshHex()
                }
                .onChange(of: editingHex) { _, editing in if !editing { refreshHex() } }
        }
        .onAppear { refreshHex() }
        .onChange(of: color) { _, _ in refreshHex() }
        .onChange(of: colorScheme) { _, _ in if !editingHex { refreshHex() } }
    }

    private func refreshHex() { hex = SyntaxPalette.hex(for: NSColor(color)) }
}
