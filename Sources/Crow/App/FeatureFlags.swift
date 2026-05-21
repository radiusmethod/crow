import Foundation

/// Crow's feature-flag bag.
///
/// Flags are decided once at app launch (`AppDelegate.launchMainApp`) and
/// frozen for the process lifetime.
public enum FeatureFlags {

    /// Route managed terminals through the tmux backend (#198 / #229).
    ///
    /// As of #301 this is the default. Set `CROW_TMUX_BACKEND=0` (or
    /// `false`/`no`/`off`) in the environment to fall back to the legacy
    /// per-terminal Ghostty backend for a launch. This escape hatch is
    /// intended for one release of soak; it will be removed in a follow-up.
    public static var tmuxBackend: Bool {
        !envExplicitlyOff("CROW_TMUX_BACKEND")
    }

    /// Returns true only when the env var is set to an explicit "off" value.
    /// An unset env var is interpreted as "default" — which is ON for tmux.
    private static func envExplicitlyOff(_ name: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[name]?.lowercased() else { return false }
        switch raw {
        case "0", "false", "no", "off": return true
        default: return false
        }
    }
}
