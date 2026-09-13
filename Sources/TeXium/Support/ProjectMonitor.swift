import Foundation
import CoreServices

final class ProjectMonitor {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void
    init(root: URL, changed: @escaping () -> Void) {
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, _, _ in
            guard let info else { return }
            let owner = Unmanaged<ProjectMonitor>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            if list.prefix(count).contains(where: { !$0.contains("/.texium-build/") && !$0.hasSuffix("/.texium-build") && !$0.contains("/.git/") }) { owner.changed() }
        }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.6, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil }
    }
    deinit { stop() }
}
