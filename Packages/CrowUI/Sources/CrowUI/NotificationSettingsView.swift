import SwiftUI
import AppKit
import CrowCore

/// Settings view for configuring notification sounds and macOS system notifications.
public struct NotificationSettingsView: View {
    @Binding var settings: NotificationSettings
    @Binding var autoRespond: AutoRespondSettings
    var onSave: (() -> Void)?

    /// Built-in macOS system sounds available for selection.
    private static let builtInSounds = NotificationSettings.builtInSounds

    public init(
        settings: Binding<NotificationSettings>,
        autoRespond: Binding<AutoRespondSettings>,
        onSave: (() -> Void)? = nil
    ) {
        self._settings = settings
        self._autoRespond = autoRespond
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            Section("Global") {
                Toggle("Mute All", isOn: $settings.globalMute)
                    .onChange(of: settings.globalMute) { _, _ in onSave?() }

                Toggle("Enable Sounds", isOn: $settings.soundEnabled)
                    .disabled(settings.globalMute)
                    .onChange(of: settings.soundEnabled) { _, _ in onSave?() }

                Toggle("Enable System Notifications", isOn: $settings.systemNotificationsEnabled)
                    .disabled(settings.globalMute)
                    .onChange(of: settings.systemNotificationsEnabled) { _, _ in onSave?() }
            }

            ForEach(NotificationEvent.allCases) { event in
                eventSection(for: event)
            }

            autoRespondSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var autoRespondSection: some View {
        Section {
            Toggle("Respond to 'changes requested' reviews", isOn: $autoRespond.respondToChangesRequested)
                .onChange(of: autoRespond.respondToChangesRequested) { _, _ in onSave?() }
            Toggle("Respond to failed CI checks", isOn: $autoRespond.respondToFailedChecks)
                .onChange(of: autoRespond.respondToFailedChecks) { _, _ in onSave?() }
            Text("When enabled, Crow types an instruction into the session's Claude Code terminal asking Claude to read the review or CI logs and address the issue. Off by default — typing into a terminal unprompted is intrusive.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-respond")
                Text("Automatically prompt Claude to fix PR feedback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func eventSection(for event: NotificationEvent) -> some View {
        let config = bindingForEvent(event)

        Section {
            Toggle("Enabled", isOn: config.enabled)
                .disabled(settings.globalMute)
                .onChange(of: config.wrappedValue.enabled) { _, _ in onSave?() }

            Picker("Sound", selection: config.soundName) {
                ForEach(Self.builtInSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .disabled(settings.globalMute || !settings.soundEnabled || !config.wrappedValue.enabled)
            .onChange(of: config.wrappedValue.soundName) { _, _ in onSave?() }

            HStack {
                Toggle("System Notification", isOn: config.systemNotificationEnabled)
                    .disabled(settings.globalMute || !settings.systemNotificationsEnabled || !config.wrappedValue.enabled)
                    .onChange(of: config.wrappedValue.systemNotificationEnabled) { _, _ in onSave?() }
            }

            Button("Preview Sound") {
                NSSound(named: config.wrappedValue.soundName)?.play()
            }
            .disabled(settings.globalMute || !settings.soundEnabled || !config.wrappedValue.enabled)
            .font(.caption)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayName)
                Text(event.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bindingForEvent(_ event: NotificationEvent) -> Binding<EventNotificationConfig> {
        Binding(
            get: { settings.config(for: event) },
            set: { settings.eventSettings[event] = $0 }
        )
    }
}
