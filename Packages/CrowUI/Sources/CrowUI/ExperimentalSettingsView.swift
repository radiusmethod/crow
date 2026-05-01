import SwiftUI
import CrowCore

/// Settings view for experimental / opt-in feature flags. Each toggle is
/// frozen at app launch — flipping it persists immediately, but the runtime
/// behavior change requires a relaunch (matches the underlying FeatureFlags
/// "decided once at startup" contract).
public struct ExperimentalSettingsView: View {
    @Binding var experimentalTmuxBackend: Bool
    var onSave: (() -> Void)?

    public init(
        experimentalTmuxBackend: Binding<Bool>,
        onSave: (() -> Void)? = nil
    ) {
        self._experimentalTmuxBackend = experimentalTmuxBackend
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Use tmux for managed terminals", isOn: $experimentalTmuxBackend)
                    .onChange(of: experimentalTmuxBackend) { _, _ in onSave?() }
                Text("Routes Claude Code terminals through a single shared Ghostty surface attached to a tmux session, instead of one libghostty surface per tab. Faster session switching, less memory, and per-session shells stay alive across UI navigation. Requires tmux ≥ 3.3 (brew install tmux). Takes effect on next app launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("tmux backend")
                    Text("Experimental — see #198 for context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
