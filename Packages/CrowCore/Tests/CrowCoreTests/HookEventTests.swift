import Foundation
import Testing
@testable import CrowCore

// MARK: - HookEvent Tests

@Test func hookEventInitDefaults() {
    let sessionID = UUID()
    let before = Date()
    let event = HookEvent(sessionID: sessionID, eventName: "Stop", summary: "Session stopped")
    let after = Date()
    #expect(event.sessionID == sessionID)
    #expect(event.eventName == "Stop")
    #expect(event.summary == "Session stopped")
    #expect(event.timestamp >= before && event.timestamp <= after)
}

@Test func hookEventCustomIDAndTimestamp() {
    let id = UUID()
    let date = Date(timeIntervalSince1970: 1_000_000)
    let event = HookEvent(id: id, sessionID: UUID(), eventName: "PreToolUse", summary: "Using Bash", timestamp: date)
    #expect(event.id == id)
    #expect(event.timestamp == date)
}

@Test func hookEventStoresAllFields() {
    let sessionID = UUID()
    let event = HookEvent(sessionID: sessionID, eventName: "Notification", summary: "Task complete")
    #expect(event.sessionID == sessionID)
    #expect(event.eventName == "Notification")
    #expect(event.summary == "Task complete")
}
