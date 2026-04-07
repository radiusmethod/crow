import Testing
import Foundation
import CrowIPC
@testable import CrowCLILib

// MARK: - Hook Event Payload Parsing

@Test func parseValidJSONPayload() throws {
    let json = #"{"key": "value", "num": 42}"#
    let data = json.data(using: .utf8)!

    let payload = parseHookPayload(from: data)

    #expect(payload["key"]?.stringValue == "value")
    #expect(payload["num"]?.intValue == 42)
}

@Test func parseEmptyDataReturnsEmptyPayload() {
    let payload = parseHookPayload(from: Data())
    #expect(payload.isEmpty)
}

@Test func parseMalformedJSONReturnsEmptyPayload() {
    let data = "not valid json".data(using: .utf8)!
    let payload = parseHookPayload(from: data)
    #expect(payload.isEmpty)
}

@Test func parseNestedJSONPayload() throws {
    let json = #"{"event": "Stop", "data": {"reason": "user"}}"#
    let data = json.data(using: .utf8)!

    let payload = parseHookPayload(from: data)

    #expect(payload["event"]?.stringValue == "Stop")
    if case .object(let nested) = payload["data"] {
        #expect(nested["reason"]?.stringValue == "user")
    } else {
        Issue.record("Expected nested object for 'data' key")
    }
}

@Test func parseArrayPayloadFails() {
    // hook-event expects a dictionary, not an array
    let json = #"[1, 2, 3]"#
    let data = json.data(using: .utf8)!

    let payload = parseHookPayload(from: data)
    #expect(payload.isEmpty)
}
