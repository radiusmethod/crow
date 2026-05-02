import ArgumentParser
import CrowIPC
import Foundation

// MARK: - Hook Event Command

/// Forward a Claude Code hook event to the running Crow app.
///
/// Reads a JSON payload from stdin (piped by Claude Code) and forwards it
/// as an RPC call. Silent on success to avoid polluting hook output.
public struct HookEventCmd: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "hook-event",
        abstract: "Forward a Claude Code hook event to the app (reads JSON from stdin)"
    )
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Event name (e.g., Stop, Notification, PreToolUse)") var event: String

    public init() {}

    public func validate() throws {
        try validateUUID(session, label: "session UUID")
    }

    public func run() throws {
        let payload = parseHookPayload(from: FileHandle.standardInput.readDataToEndOfFile())
        try forwardHookEvent(sessionID: session, eventName: event, payload: payload)
    }
}

/// Forward a parsed hook event over the Unix socket.
///
/// Silently no-ops when the Crow app is not running (socket connection
/// refused or socket file absent). Hooks are fire-and-forget — a missing
/// listener is an expected state, not an error, so we must not exit
/// non-zero or write to stderr (it pollutes Claude Code's hook output).
/// Other socket errors (timeout, write/read failures) and JSON-RPC
/// errors still propagate so genuine misbehavior is visible.
func forwardHookEvent(sessionID: String, eventName: String, payload: [String: JSONValue]) throws {
    do {
        let result = try rpc("hook-event", params: [
            "session_id": .string(sessionID),
            "event_name": .string(eventName),
            "payload": .object(payload),
        ])

        // Silent on success — only print on error
        if result["error"] != nil {
            printJSON(result)
        }
    } catch SocketError.connectionFailed {
        return
    }
}

/// Parse a JSON payload from stdin data for hook events.
///
/// Returns the decoded dictionary, or an empty dictionary if the data is empty or
/// cannot be parsed (with a warning written to stderr).
func parseHookPayload(from data: Data) -> [String: JSONValue] {
    guard !data.isEmpty else { return [:] }
    do {
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    } catch {
        FileHandle.standardError.write(
            "crow: warning: failed to parse stdin JSON: \(error.localizedDescription)\n"
                .data(using: .utf8)!
        )
        return [:]
    }
}
