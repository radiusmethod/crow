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

        let result = try rpc("hook-event", params: [
            "session_id": .string(session),
            "event_name": .string(event),
            "payload": .object(payload),
        ])

        // Silent on success — only print on error
        if result["error"] != nil {
            printJSON(result)
        }
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
