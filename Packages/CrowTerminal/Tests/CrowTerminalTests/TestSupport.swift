import Foundation

/// Locate a tmux binary on the host, in priority order. Module-internal so
/// `.enabled(if: tmuxBinaryAvailable)` traits can reference it across test
/// files without the macro hitting a circular-reference resolution.
let discoveredTmuxBinary: String? = {
    let candidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}()
