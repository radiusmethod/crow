import Foundation
import RmCore

/// Persisted data structure.
public struct StoreData: Codable, Sendable {
    public var sessions: [Session]
    public var worktrees: [SessionWorktree]
    public var links: [SessionLink]
    public var terminals: [SessionTerminal]

    public init(
        sessions: [Session] = [],
        worktrees: [SessionWorktree] = [],
        links: [SessionLink] = [],
        terminals: [SessionTerminal] = []
    ) {
        self.sessions = sessions
        self.worktrees = worktrees
        self.links = links
        self.terminals = terminals
    }
}

/// Thread-safe JSON file store for session persistence.
public final class JSONStore: Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private nonisolated(unsafe) var _data: StoreData

    public var data: StoreData {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("rm-ai-ide", isDirectory: true)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("store.json")

        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self._data = (try? decoder.decode(StoreData.self, from: data)) ?? StoreData()
        } else {
            self._data = StoreData()
        }
    }

    public func mutate(_ transform: (inout StoreData) -> Void) {
        lock.lock()
        transform(&_data)
        let snapshot = _data
        lock.unlock()
        Self.save(snapshot, to: fileURL)
    }

    private static func save(_ data: StoreData, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(data) else { return }
        try? jsonData.write(to: url, options: .atomic)
    }
}
