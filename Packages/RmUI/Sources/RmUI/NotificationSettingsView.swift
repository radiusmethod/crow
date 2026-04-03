import SwiftUI
import AppKit
import RmCore

/// Settings view for configuring notification sounds and macOS system notifications.
public struct NotificationSettingsView: View {
    @Binding var settings: NotificationSettings

    public init(settings: Binding<NotificationSettings>) {
        self._settings = settings
    }

    /// Built-in macOS system sounds available for selection.
    private static let builtInSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink",
    ]

    public var body: some View {
        Form {
            Section("Global") {
                Toggle("Mute All", isOn: $settings.globalMute)
                    .help("Suppress all notification sounds and system notifications")

                Toggle("Enable Sounds", isOn: $settings.soundEnabled)
                    .disabled(settings.globalMute)

                Toggle("Enable System Notifications", isOn: $settings.systemNotificationsEnabled)
                    .disabled(settings.globalMute)
            }

            Section("Event Notifications") {
                ForEach(NotificationEvent.allCases) { event in
                    eventRow(for: event)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func eventRow(for event: NotificationEvent) -> some View {
        let config = bindingForEvent(event)

        DisclosureGroup {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Sound", isOn: config.soundEnabled)
                        .disabled(settings.globalMute || !settings.soundEnabled)

                    Toggle("System Notification", isOn: config.systemNotificationEnabled)
                        .disabled(settings.globalMute || !settings.systemNotificationsEnabled)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Picker("Sound", selection: config.soundName) {
                        ForEach(Self.builtInSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(width: 140)
                    .disabled(settings.globalMute || !settings.soundEnabled || !config.wrappedValue.soundEnabled)

                    Button("Preview") {
                        NSSound(named: config.wrappedValue.soundName)?.play()
                    }
                    .font(.caption)
                    .disabled(settings.globalMute || !settings.soundEnabled)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Toggle(isOn: config.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.displayName)
                            .fontWeight(.medium)
                        Text(event.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(settings.globalMute)
            }
        }
    }

    /// Create a binding into `eventSettings` for a specific event, initializing defaults if missing.
    private func bindingForEvent(_ event: NotificationEvent) -> Binding<EventNotificationConfig> {
        Binding(
            get: { settings.config(for: event) },
            set: { settings.eventSettings[event] = $0 }
        )
    }
}
