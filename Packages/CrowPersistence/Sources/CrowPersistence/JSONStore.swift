import Foundation
import CrowCore

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
        let dir = directory ?? {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let crowDir = appSupport.appendingPathComponent("crow", isDirectory: true)
            // One-time migration: copy data from old "rm-ai-ide" directory if it exists
            let oldDir = appSupport.appendingPathComponent("rm-ai-ide", isDirectory: true)
            if !FileManager.default.fileExists(atPath: crowDir.path),
               FileManager.default.fileExists(atPath: oldDir.path) {
                try? FileManager.default.copyItem(at: oldDir, to: crowDir)
                NSLog("[JSONStore] Migrated data from rm-ai-ide to crow")
            }
            return crowDir
        }()

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("store.json")

        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                self._data = try decoder.decode(StoreData.self, from: data)
            } catch {
                // Log the error so we know WHY decoding failed — this was silently wiping the store
                NSLog("[JSONStore] ERROR: Failed to decode store.json: \(error.localizedDescription)")
                NSLog("[JSONStore] Backing up corrupt store to store.json.bak")
                let backupURL = dir.appendingPathComponent("store.json.bak")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
                self._data = StoreData()
            }
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
        guard let jsonData = try? encoder.encode(data) else {
            NSLog("[JSONStore] ERROR: Failed to encode store data")
            return
        }
        do {
            try jsonData.write(to: url, options: .atomic)
            // Restrict store file to owner-only access
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("[JSONStore] ERROR: Failed to write store.json: \(error.localizedDescription)")
        }
    }
}
