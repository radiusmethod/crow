import AppKit
import UserNotifications
import RmCore
import RmIPC

/// Manages sound playback and macOS notification center alerts for hook events.
@MainActor
final class NotificationManager {
    private let appState: AppState
    private var settings: NotificationSettings
    private var soundCache: [String: NSSound] = [:]
    private var lastNotified: [UUID: (event: NotificationEvent, time: Date)] = [:]

    /// Available built-in macOS system sounds.
    static let builtInSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink",
    ]

    init(appState: AppState, settings: NotificationSettings) {
        self.appState = appState
        self.settings = settings
        requestNotificationPermission()
    }

    func updateSettings(_ settings: NotificationSettings) {
        self.settings = settings
    }

    // MARK: - Event Handling

    /// Called from the hook-event handler after state machine updates.
    func handleEvent(
        sessionID: UUID,
        eventName: String,
        payload: [String: JSONValue],
        summary: String
    ) {
        let toolName = payload["tool_name"]?.stringValue
        let notificationType = payload["notification_type"]?.stringValue

        guard let event = NotificationEvent.from(
            eventName: eventName,
            toolName: toolName,
            notificationType: notificationType
        ) else { return }

        guard !settings.globalMute else { return }

        let config = settings.config(for: event)
        guard config.enabled else { return }

        // Deduplicate: skip if same (session, event) fired within 2 seconds
        if let last = lastNotified[sessionID],
           last.event == event,
           Date().timeIntervalSince(last.time) < 2.0 {
            return
        }
        lastNotified[sessionID] = (event, Date())

        // Play sound
        if settings.soundEnabled && config.soundEnabled {
            playSound(named: config.soundName)
        }

        // Post system notification (only when user isn't looking at this session)
        if settings.systemNotificationsEnabled && config.systemNotificationEnabled {
            let appFocused = NSApp.isActive
            let sessionVisible = appState.selectedSessionID == sessionID
            if !appFocused || !sessionVisible {
                let sessionName = appState.sessions.first(where: { $0.id == sessionID })?.name ?? "Session"
                postSystemNotification(
                    title: "\(event.displayName) — \(sessionName)",
                    body: summary,
                    sessionID: sessionID,
                    eventName: eventName
                )
            }
        }
    }

    // MARK: - Sound Playback

    private func playSound(named name: String) {
        if let cached = soundCache[name] {
            cached.stop()
            cached.play()
            return
        }

        // Try built-in macOS sound
        if let sound = NSSound(named: name) {
            soundCache[name] = sound
            sound.play()
            return
        }

        // Try as a file path (custom sound)
        let url = URL(fileURLWithPath: name)
        if FileManager.default.fileExists(atPath: name),
           let sound = NSSound(contentsOf: url, byReference: true) {
            soundCache[name] = sound
            sound.play()
        }
    }

    // MARK: - System Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("Notification permission error: \(error)")
            }
        }
    }

    private func postSystemNotification(
        title: String,
        body: String,
        sessionID: UUID,
        eventName: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let identifier = "\(sessionID.uuidString)-\(eventName)-\(Int(Date().timeIntervalSince1970))"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Failed to post notification: \(error)")
            }
        }
    }
}
