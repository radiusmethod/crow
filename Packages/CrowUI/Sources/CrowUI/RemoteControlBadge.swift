import SwiftUI
import CrowCore

/// Small antenna indicator shown on sessions whose Claude Code was launched with `--rc`.
///
/// The indicator is driven by `AppState.remoteControlActiveTerminals` so it stays accurate
/// even after the user toggles the global setting mid-session — only sessions that actually
/// started with `--rc` are flagged.
struct RemoteControlBadge: View {
    var compact: Bool = false

    var body: some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: compact ? 10 : 12, weight: .semibold))
            .foregroundStyle(CorveilTheme.gold)
            .help("Remote control is active — this session can be driven from claude.ai")
            .accessibilityLabel("Remote control active")
    }
}

extension AppState {
    /// Whether any terminal belonging to `sessionID` was launched with remote control.
    func isRemoteControlActive(sessionID: UUID) -> Bool {
        let terminals = terminals(for: sessionID)
        return terminals.contains { remoteControlActiveTerminals.contains($0.id) }
    }
}
