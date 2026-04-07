import Foundation
import Testing
@testable import CrowCore

@Suite("SessionTerminal Codable")
struct SessionTerminalTests {

    // MARK: - Round-trip

    @Test func fullRoundTrip() throws {
        let terminal = SessionTerminal(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Claude Code",
            cwd: "/Users/test/project",
            command: "claude --continue",
            isManaged: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(terminal)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(SessionTerminal.self, from: data)

        #expect(decoded.id == terminal.id)
        #expect(decoded.sessionID == terminal.sessionID)
        #expect(decoded.name == terminal.name)
        #expect(decoded.cwd == terminal.cwd)
        #expect(decoded.command == terminal.command)
        #expect(decoded.isManaged == true)
        #expect(decoded.createdAt == terminal.createdAt)
    }

    // MARK: - Backward Compatibility

    @Test func missingIsManagedDefaultsToFalse() throws {
        let json = """
        {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "name": "Shell",
            "cwd": "/Users/test",
            "createdAt": 1700000000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let terminal = try decoder.decode(SessionTerminal.self, from: json)

        #expect(terminal.isManaged == false)
    }

    @Test func missingCommandDefaultsToNil() throws {
        let json = """
        {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "name": "Shell",
            "cwd": "/Users/test",
            "createdAt": 1700000000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let terminal = try decoder.decode(SessionTerminal.self, from: json)

        #expect(terminal.command == nil)
    }

    @Test func isManagedTrueDecodesCorrectly() throws {
        let json = """
        {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "name": "Claude Code",
            "cwd": "/Users/test",
            "isManaged": true,
            "createdAt": 1700000000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let terminal = try decoder.decode(SessionTerminal.self, from: json)

        #expect(terminal.isManaged == true)
    }
}
