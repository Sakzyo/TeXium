import SwiftUI
import AppKit

struct WindowLifecycle: NSViewRepresentable {
    let session: ProjectSession
    func makeCoordinator() -> Coordinator { Coordinator(session) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.previous = window.delegate
            window.delegate = context.coordinator
            window.setFrameAutosaveName("TeXium-" + session.metadata.lastPathComponent)
            window.representedURL = session.root
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { view.window?.isDocumentEdited = session.buffers.values.contains(where: \.dirty) }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let session: ProjectSession
        weak var previous: NSWindowDelegate?
        init(_ session: ProjectSession) { self.session = session }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard session.gitTask == nil else { session.error = "Wait for Git to finish, or stop it in the Git inspector, before closing this project."; return false }
            do { try session.saveAllSynchronously(); return previous?.windowShouldClose?(sender) ?? true }
            catch { session.present(error); return false }
        }
        func windowWillClose(_ notification: Notification) { session.shutdown(); previous?.windowWillClose?(notification) }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || previous?.responds(to: selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
    }
}
