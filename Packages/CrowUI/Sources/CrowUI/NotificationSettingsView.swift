import SwiftUI
import AppKit
import CrowCore

/// Settings view for configuring notification sounds and macOS system notifications.
public struct NotificationSettingsView: View {
    @Binding var settings: NotificationSettings
    var onSave: (() -> Void)?

    /// Built-in macOS system sounds available for selection.
    private static let builtInSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink",
    ]

    public init(settings: Binding<NotificationSettings>, onSave: (() -> Void)? = nil) {
        self._settings = settings
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
        }
        .formStyle(.grouped)
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
