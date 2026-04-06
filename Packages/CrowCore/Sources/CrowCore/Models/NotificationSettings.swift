import Foundation

/// Notification preferences stored in AppConfig.
///
/// Notifications follow a cascading disable model:
/// 1. `globalMute` overrides everything — no sounds or system notifications.
/// 2. `soundEnabled` / `systemNotificationsEnabled` act as global category toggles.
/// 3. Per-event settings in `eventSettings` provide fine-grained control.
///
/// A notification only fires if the global toggle, the category toggle, **and** the
/// per-event toggle are all enabled.
public struct NotificationSettings: Codable, Sendable, Equatable {
    /// Master mute — suppresses all sounds and system notifications.
    public var globalMute: Bool

    /// Global toggle for sound playback.
    public var soundEnabled: Bool

    /// Global toggle for macOS notification center alerts.
    public var systemNotificationsEnabled: Bool

    /// Per-event-category configuration.
    public var eventSettings: [NotificationEvent: EventNotificationConfig]

    public init(
        globalMute: Bool = false,
        soundEnabled: Bool = true,
        systemNotificationsEnabled: Bool = true,
        eventSettings: [NotificationEvent: EventNotificationConfig]? = nil
    ) {
        self.globalMute = globalMute
        self.soundEnabled = soundEnabled
        self.systemNotificationsEnabled = systemNotificationsEnabled
        if let eventSettings {
            self.eventSettings = eventSettings
        } else {
            // Populate defaults for all event categories
            var defaults: [NotificationEvent: EventNotificationConfig] = [:]
            for event in NotificationEvent.allCases {
                defaults[event] = EventNotificationConfig(soundName: event.defaultSound)
            }
            self.eventSettings = defaults
        }
    }

    /// Get the config for a specific event, falling back to defaults.
    ///
    /// This ensures forward compatibility: when a new `NotificationEvent` case is added,
    /// existing config files that don't include it in `eventSettings` still get sensible defaults.
    public func config(for event: NotificationEvent) -> EventNotificationConfig {
        eventSettings[event] ?? EventNotificationConfig(soundName: event.defaultSound)
    }
}

/// Per-event notification configuration.
public struct EventNotificationConfig: Codable, Sendable, Equatable {
    /// Whether this event category triggers any notification at all.
    public var enabled: Bool

    /// Whether to play a sound for this event.
    public var soundEnabled: Bool

    /// Whether to post a macOS system notification.
    public var systemNotificationEnabled: Bool

    /// Name of the sound to play (macOS system sound name or path to custom file).
    public var soundName: String

    public init(
        enabled: Bool = true,
        soundEnabled: Bool = true,
        systemNotificationEnabled: Bool = true,
        soundName: String = "Glass"
    ) {
        self.enabled = enabled
        self.soundEnabled = soundEnabled
        self.systemNotificationEnabled = systemNotificationEnabled
        self.soundName = soundName
    }
}
