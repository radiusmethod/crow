import Foundation

/// Crow's feature-flag bag.
///
/// Flags are read from the process environment so they can be flipped per
/// app launch without a rebuild. They're decided once at app launch
/// (`AppDelegate.launchMainApp`) and frozen for the process lifetime.
public enum FeatureFlags {

    /// `CROW_TMUX_BACKEND=1` — route new SessionTerminals through the tmux
    /// backend (#198) instead of the per-terminal Ghostty surface model.
    /// Off by default; flipping it to `1` is the gated rollout entry point.
    public static var tmuxBackend: Bool {
        boolFlag("CROW_TMUX_BACKEND")
    }

    private static func boolFlag(_ name: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[name] else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }
}
