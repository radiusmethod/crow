import Foundation
import Testing
@testable import CrowCore

// MARK: - HookNotification Tests

@Test func hookNotificationStoresAllFields() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let notif = HookNotification(message: "Task finished", notificationType: "info", timestamp: date)
    #expect(notif.message == "Task finished")
    #expect(notif.notificationType == "info")
    #expect(notif.timestamp == date)
}

@Test func hookNotificationDefaultTimestamp() {
    let before = Date()
    let notif = HookNotification(message: "Alert", notificationType: "warning")
    let after = Date()
    #expect(notif.timestamp >= before && notif.timestamp <= after)
}
