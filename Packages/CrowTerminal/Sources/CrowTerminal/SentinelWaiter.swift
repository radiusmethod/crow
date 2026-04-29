import Foundation

/// Polls for a sentinel file's first appearance.
///
/// The bundled `crow-shell-wrapper.sh` `touch`es a per-terminal sentinel
/// file on every shell prompt (zsh: `precmd`, bash: `PROMPT_COMMAND`).
/// First appearance = the shell has reached its first interactive prompt
/// = ready to accept input.
///
/// This replaces the historical 5-second sleep at
/// `TerminalManager.surfaceDidCreate` for tmux-backed terminals. The
/// sentinel approach is tmux-agnostic — the wrapper writes directly to
/// disk, bypassing the tmux emulator's escape-sequence handling.
///
/// See `docs/tmux-backend-spec.md` §6 for the rationale and the empirical
/// numbers from the spike (zsh 172ms / bash 231ms first-prompt latency
/// without tmux; sub-50ms through tmux).
public struct SentinelWaiter: Sendable {

    public init() {}

    /// Wait for `sentinelPath` to exist, polling every `pollInterval`.
    /// Returns the elapsed time on first appearance, or `nil` on timeout.
    ///
    /// - Parameters:
    ///   - sentinelPath: per-terminal sentinel path the wrapper touches.
    ///   - timeout: max wait. Default 5s — same budget as the historical
    ///     sleep, but typical values are sub-second.
    ///   - pollInterval: poll cadence. Default 50ms — cheap; the file
    ///     stat is a single syscall.
    public func waitForPrompt(
        sentinelPath: String,
        timeout: TimeInterval = 5.0,
        pollInterval: TimeInterval = 0.05
    ) async -> TimeInterval? {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        let nanosPerInterval = UInt64(pollInterval * 1_000_000_000)
        let fm = FileManager.default
        while Date() < deadline {
            if fm.fileExists(atPath: sentinelPath) {
                return Date().timeIntervalSince(start)
            }
            try? await Task.sleep(nanoseconds: nanosPerInterval)
        }
        return nil
    }
}
