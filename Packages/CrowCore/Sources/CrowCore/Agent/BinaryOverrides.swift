import Foundation

/// Process-wide explicit overrides for `CodingAgent.findBinary()`. Populated
/// once at app launch from `AppConfig.defaults.binaries` and consulted by the
/// default `findBinary()` impl before falling through to PATH-walk + hardcoded
/// candidates (CROW-484).
///
/// Keyed by `AgentKind` so a config entry like
/// `{ "defaults": { "binaries": { "codex": "/Users/me/.nvm/.../bin/codex" } } }`
/// pins the codex agent's binary to the explicit path the user named — useful
/// when discovery still fails for some exotic install layout.
public final class BinaryOverrides: @unchecked Sendable {
    public static let shared = BinaryOverrides()

    private let lock = NSLock()
    private var paths: [AgentKind: String] = [:]

    /// Replace the override map. Keys are `AgentKind.rawValue` strings (matches
    /// the JSON config shape and the existing `agentsByKind` keying style).
    /// An empty map clears all overrides.
    public func set(_ raw: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        paths = Dictionary(uniqueKeysWithValues: raw.map { (AgentKind(rawValue: $0), $1) })
    }

    /// The user-configured absolute path for `kind`, or `nil` if none is set.
    /// Callers must still verify the path is executable before using it — a
    /// stale override (e.g. the binary moved after config edit) should fall
    /// through to PATH-walk rather than break agent registration.
    public func path(for kind: AgentKind) -> String? {
        lock.lock(); defer { lock.unlock() }
        return paths[kind]
    }
}
