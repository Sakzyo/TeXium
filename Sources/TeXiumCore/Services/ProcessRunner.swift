import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let status: Int32
    public let output: String
}

/// A pipe is drained on a worker queue while the process runs. Cancellation is
/// remembered even when it arrives before Process.run(), and kills descendants.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}

    public func run(executable: URL, arguments: [String], directory: URL, environment: [String: String]? = nil, output: (@Sendable (String) -> Void)? = nil) async throws -> ProcessResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let task = Process(); let pipe = Pipe()
                    task.executableURL = executable; task.arguments = arguments; task.currentDirectoryURL = directory
                    task.environment = environment ?? ProcessInfo.processInfo.environment
                    task.standardOutput = pipe; task.standardError = pipe
                    task.standardInput = FileHandle.nullDevice
                    do {
                        lock.lock()
                        if cancelled { lock.unlock(); throw CancellationError() }
                        process = task
                        do { try task.run() } catch { process = nil; lock.unlock(); throw error }
                        lock.unlock()
                        try? pipe.fileHandleForWriting.close()
                        var all = Data()
                        while true {
                            let data = pipe.fileHandleForReading.availableData
                            if data.isEmpty { break }
                            all.append(data); output?(String(decoding: data, as: UTF8.self))
                        }
                        task.waitUntilExit()
                        lock.lock(); process = nil; let wasCancelled = cancelled; lock.unlock()
                        if wasCancelled { throw CancellationError() }
                        continuation.resume(returning: ProcessResult(status: task.terminationStatus, output: String(decoding: all, as: UTF8.self)))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.cancel() }
    }

    public func cancel() {
        lock.lock(); cancelled = true; let active = process; lock.unlock()
        guard let active else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard active.isRunning else { return }
            let rootPID = active.processIdentifier
            // Freeze the parent before listing the process tree so latexmk cannot
            // start a replacement engine while cancellation walks its children.
            kill(rootPID, SIGSTOP)
            func descendants(_ pid: pid_t) -> [pid_t] {
                var buffer = [pid_t](repeating: 0, count: 4096)
                let size = Int32(buffer.count * MemoryLayout<pid_t>.size)
                let count = proc_listchildpids(pid, &buffer, size)
                guard count > 0 else { return [] }
                let children = Array(buffer.prefix(Int(count))).filter { $0 > 0 }
                for child in children { kill(child, SIGSTOP) }
                return children.flatMap { descendants($0) + [$0] }
            }
            let children = descendants(rootPID)
            for pid in children { kill(pid, SIGKILL) }
            kill(rootPID, SIGKILL)
        }
    }
}
