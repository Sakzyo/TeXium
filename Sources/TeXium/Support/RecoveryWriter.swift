import Foundation

actor RecoveryWriter {
    private var latest = 0
    func write(_ buffers: [String: String], generation: Int, to url: URL) throws {
        guard generation >= latest else { return }
        latest = generation
        try JSONEncoder().encode(buffers).write(to: url, options: .atomic)
    }
}
