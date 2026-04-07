import ArgumentParser
import CrowIPC
import Foundation

// MARK: - Metadata Commands

/// Set ticket metadata (URL, title, number) for a session.
///
/// At least one of `--url`, `--title`, or `--number` must be provided.
public struct SetTicket: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "set-ticket", abstract: "Set ticket metadata")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Ticket URL") var url: String?
    @Option(name: .long, help: "Ticket title") var title: String?
    @Option(name: .long, help: "Ticket number") var number: Int?

    public init() {}

    public func validate() throws {
        try validateUUID(session, label: "session UUID")
        try validateSetTicketHasField(url: url, title: title, number: number)
    }

    public func run() throws {
        var params: [String: JSONValue] = ["session_id": .string(session)]
        if let url { params["url"] = .string(url) }
        if let title { params["title"] = .string(title) }
        if let number { params["number"] = .int(number) }
        let result = try rpc("set-ticket", params: params)
        printJSON(result)
    }
}

/// Add a link to a session.
public struct AddLink: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "add-link", abstract: "Add a link to a session")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Link label") var label: String
    @Option(name: .long, help: "Link URL") var url: String
    @Option(name: .long, help: "Link type: ticket, pr, repo, custom") var type: String = "custom"

    public init() {}

    public func validate() throws {
        try validateUUID(session, label: "session UUID")
        try validateLinkType(type)
    }

    public func run() throws {
        let result = try rpc("add-link", params: [
            "session_id": .string(session),
            "label": .string(label),
            "url": .string(url),
            "type": .string(type),
        ])
        printJSON(result)
    }
}

/// List all links for a session.
public struct ListLinks: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "list-links", abstract: "List links for a session")
    @Option(name: .long, help: "Session UUID") var session: String

    public init() {}

    public func validate() throws {
        try validateUUID(session, label: "session UUID")
    }

    public func run() throws {
        let result = try rpc("list-links", params: ["session_id": .string(session)])
        printJSON(result)
    }
}
