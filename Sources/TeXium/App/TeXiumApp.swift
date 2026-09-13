import SwiftUI
import AppKit

@main
struct TeXiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = ProjectLibrary()
    var body: some Scene {
        WindowGroup("TeXium", id: "browser") {
            ProjectBrowser(library: library)
        }
        .defaultSize(width: 860, height: 560)
        .commands { TeXiumCommands(library: library) }

        WindowGroup("Project", id: "project", for: String.self) { $path in
            if let path { ProjectWindow(root: URL(fileURLWithPath: path), library: library) }
        }
        .defaultSize(width: 1440, height: 900)

        Settings { SettingsView() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSignal: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume(); terminationSignal = source
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for session in ProjectSession.openSessions.allObjects {
            do { try session.saveAllSynchronously() }
            catch {
                let alert = NSAlert(); alert.messageText = "Your edits need attention before quitting"
                alert.informativeText = error.localizedDescription + " Your recovery copy is retained."
                alert.addButton(withTitle: "Keep Editing"); alert.runModal()
                return .terminateCancel
            }
            session.stopBuild()
        }
        UserDefaults.standard.set(ProjectSession.openSessions.allObjects.map { $0.root.path }, forKey: "openProjectWindows")
        return .terminateNow
    }
}
