import Foundation

/// Helpers for building the argument string appended to a `claude` shell invocation.
///
/// Centralized so worker-session launches, the Manager tab, and crow-CLI-spawned
/// terminals all produce consistent flags — and so the logic is independently testable.
public enum ClaudeLaunchArgs {
    /// POSIX single-quote escape for safe interpolation into a shell command line.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Flags to append after the `claude` binary path when remote control is enabled.
    ///
    /// Returns a string beginning with a leading space — e.g. `" --rc --name 'Manager'"`
    /// — or an empty string when `remoteControl` is `false`. The `--name` flag makes the
    /// session show up with a recognizable label in claude.ai's Remote Control panel.
    public static func argsSuffix(remoteControl: Bool, sessionName: String?) -> String {
        guard remoteControl else { return "" }
        var s = " --rc"
        if let name = sessionName, !name.isEmpty {
            s += " --name \(shellQuote(name))"
        }
        return s
    }
}
