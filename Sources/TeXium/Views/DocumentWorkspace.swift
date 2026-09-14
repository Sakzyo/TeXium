import AppKit
import SwiftUI

/// A sizing boundary for the native source/PDF split inside SwiftUI's sidebars.
struct DocumentWorkspace: NSViewRepresentable {
    let session: ProjectSession

    func makeNSView(context: Context) -> NSHostingView<DocumentPanes> {
        let view = NSHostingView(rootView: DocumentPanes(session: session))
        // The enclosing GeometryReader already supplies the usable detail rect.
        // Inheriting the window's inspector inset here gives HSplitView both a
        // zero trailing edge and a nonzero safe-area trailing edge on macOS 26.
        view.safeAreaRegions = []
        view.sizingOptions = []
        return view
    }

    func updateNSView(_ view: NSHostingView<DocumentPanes>, context: Context) {
        // The hosted panes observe this window's session directly. Replacing
        // their root on each keystroke would needlessly disturb native layout.
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<DocumentPanes>, context: Context) -> CGSize? {
        let size = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 640, height: 600))
        // Never ask the nested native split for its fitting size while AppKit
        // is updating the surrounding window's constraints.
        return CGSize(width: size.width.isFinite ? max(0, size.width) : 640,
                      height: size.height.isFinite ? max(0, size.height) : 600)
    }
}

struct DocumentPanes: View {
    @Bindable var session: ProjectSession

    var body: some View {
        HSplitView {
            if session.layout != "PDF" {
                EditorPane(session: session).frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            if session.layout != "Source" {
                PDFPreview(session: session).frame(minWidth: 290, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
