import Foundation

/// Crow's feature-flag bag.
///
/// Flags are decided once at app launch (`AppDelegate.launchMainApp`) and
/// frozen for the process lifetime. They can be driven by either:
///   - Environment variable (CI / dev iteration without persisting state).
///   - User preference loaded from `AppConfig` and surfaced in Settings →
///     Experimental.
///
/// The two sources are OR-merged: if either says ON, the flag is ON.
public enum FeatureFlags {

    /// `CROW_TMUX_BACKEND=1` OR `Settings → Experimental → Use tmux for
    /// managed terminals` — route new SessionTerminals through the tmux
    /// backend (#198) instead of the per-terminal Ghostty surface model.
    /// Off by default; the gated rollout entry point.
    public static var tmuxBackend: Bool {
        boolFlag("CROW_TMUX_BACKEND") || tmuxBackendConfigOverride
    }

    /// User-level enable for the tmux backend, set once at launch from the
    /// loaded `AppConfig.experimentalTmuxBackend`. Frozen for the process
    /// lifetime to match the "requires restart" semantics — toggling the UI
    /// does NOT live-update this; the user must relaunch the app for a flip
    /// to take effect.
    ///
    /// `nonisolated(unsafe)` is correct here: the value is written exactly
    /// once on the main thread during `launchMainApp()`, before any reader
    /// runs. After that initial write the value is read-only for the
    /// process lifetime, so concurrent reads are safe without further
    /// synchronization.
    nonisolated(unsafe) public static var tmuxBackendConfigOverride: Bool = false

    private static func boolFlag(_ name: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[name] else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }
}
