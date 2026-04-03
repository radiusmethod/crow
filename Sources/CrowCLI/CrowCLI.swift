import ArgumentParser
import Foundation
import CrowIPC

@main
struct Crow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crow",
        abstract: "CLI for Crow — manage sessions, terminals, and metadata",
        version: "0.1.0",
        subcommands: [
            Setup.self,
            NewSession.self,
            RenameSession.self,
            SelectSession.self,
            ListSessions.self,
            GetSession.self,
            SetStatus.self,
            DeleteSession.self,
            SetTicket.self,
            AddWorktree.self,
            ListWorktrees.self,
            NewTerminal.self,
            ListTerminals.self,
            Send.self,
            AddLink.self,
            ListLinks.self,
            HookEventCmd.self,
        ]
    )
}

// MARK: - Shared Helper

func rpc(_ method: String, params: [String: JSONValue] = [:]) throws -> [String: JSONValue] {
    let client = SocketClient()
    let response = try client.send(method: method, params: params)
    if let error = response.error {
        throw ValidationError("Error \(error.code): \(error.message)")
    }
    return response.result ?? [:]
}

func printJSON(_ dict: [String: JSONValue]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(dict), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

// MARK: - Session Commands

struct NewSession: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "new-session", abstract: "Create a new session")
    @Option(name: .long, help: "Session name") var name: String

    func run() throws {
        let result = try rpc("new-session", params: ["name": .string(name)])
        printJSON(result)
    }
}

struct RenameSession: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rename-session", abstract: "Rename a session")
    @Option(name: .long, help: "Session UUID") var session: String
    @Argument(help: "New name") var name: String

    func run() throws {
        let result = try rpc("rename-session", params: ["session_id": .string(session), "name": .string(name)])
        printJSON(result)
    }
}

struct SelectSession: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "select-session", abstract: "Switch to a session")
    @Option(name: .long, help: "Session UUID") var session: String

    func run() throws {
        let result = try rpc("select-session", params: ["session_id": .string(session)])
        printJSON(result)
    }
}

struct ListSessions: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list-sessions", abstract: "List all sessions")

    func run() throws {
        let result = try rpc("list-sessions")
        printJSON(result)
    }
}

struct GetSession: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get-session", abstract: "Get session details")
    @Option(name: .long, help: "Session UUID") var session: String

    func run() throws {
        let result = try rpc("get-session", params: ["session_id": .string(session)])
        printJSON(result)
    }
}

struct SetStatus: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set-status", abstract: "Set session status")
    @Option(name: .long, help: "Session UUID") var session: String
    @Argument(help: "Status: active, paused, inReview, completed, archived") var status: String

    func run() throws {
        let result = try rpc("set-status", params: ["session_id": .string(session), "status": .string(status)])
        printJSON(result)
    }
}

struct DeleteSession: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete-session", abstract: "Delete a session")
    @Option(name: .long, help: "Session UUID") var session: String

    func run() throws {
        let result = try rpc("delete-session", params: ["session_id": .string(session)])
        printJSON(result)
    }
}

// MARK: - Metadata Commands

struct SetTicket: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set-ticket", abstract: "Set ticket metadata")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Ticket URL") var url: String?
    @Option(name: .long, help: "Ticket title") var title: String?
    @Option(name: .long, help: "Ticket number") var number: Int?

    func run() throws {
        var params: [String: JSONValue] = ["session_id": .string(session)]
        if let url { params["url"] = .string(url) }
        if let title { params["title"] = .string(title) }
        if let number { params["number"] = .int(number) }
        let result = try rpc("set-ticket", params: params)
        printJSON(result)
    }
}

// MARK: - Worktree Commands

struct AddWorktree: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add-worktree", abstract: "Register a worktree for a session")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Repo name") var repo: String
    @Option(name: .long, help: "Worktree path") var path: String
    @Option(name: .long, help: "Branch name") var branch: String
    @Option(name: .customLong("repo-path"), help: "Main repo path (for git commands)") var repoPath: String?
    @Flag(name: .long, help: "Mark as primary worktree") var primary: Bool = false

    func run() throws {
        var params: [String: JSONValue] = [
            "session_id": .string(session),
            "repo": .string(repo),
            "path": .string(path),
            "branch": .string(branch),
        ]
        if let repoPath { params["repo_path"] = .string(repoPath) }
        if primary { params["primary"] = .bool(true) }
        let result = try rpc("add-worktree", params: params)
        printJSON(result)
    }
}

struct ListWorktrees: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list-worktrees", abstract: "List worktrees for a session")
    @Option(name: .long, help: "Session UUID") var session: String

    func run() throws {
        let result = try rpc("list-worktrees", params: ["session_id": .string(session)])
        printJSON(result)
    }
}

// MARK: - Terminal Commands

struct NewTerminal: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "new-terminal", abstract: "Create a terminal in a session")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Working directory") var cwd: String
    @Option(name: .long, help: "Terminal name") var name: String?
    @Option(name: .long, help: "Command to run") var command: String?

    func run() throws {
        var params: [String: JSONValue] = [
            "session_id": .string(session),
            "cwd": .string(cwd),
        ]
        if let name { params["name"] = .string(name) }
        if let command { params["command"] = .string(command) }
        let result = try rpc("new-terminal", params: params)
        printJSON(result)
    }
}

struct ListTerminals: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list-terminals", abstract: "List terminals for a session")
    @Option(name: .long, help: "Session UUID") var session: String

    func run() throws {
        let result = try rpc("list-terminals", params: ["session_id": .string(session)])
        printJSON(result)
    }
}

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "send", abstract: "Send text to a terminal")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Terminal UUID") var terminal: String
    @Argument(help: "Text to send") var text: String

    func run() throws {
        let result = try rpc("send", params: [
            "session_id": .string(session),
            "terminal_id": .string(terminal),
            "text": .string(text),
        ])
        printJSON(result)
    }
}

// MARK: - Link Commands

struct AddLink: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add-link", abstract: "Add a link to a session")
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Link label") var label: String
    @Option(name: .long, help: "Link URL") var url: String
    @Option(name: .long, help: "Link type: ticket, pr, repo, custom") var type: String = "custom"

    func run() throws {
        let result = try rpc("add-link", params: [
            "session_id": .string(session),
            "label": .string(label),
            "url": .string(url),
            "type": .string(type),
        ])
        printJSON(result)
    }
}

struct ListLinks: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list-links", abstract: "List links for a session")
    @Option(name: .long, help: "Session UUID") var session: String

    func run() throws {
        let result = try rpc("list-links", params: ["session_id": .string(session)])
        printJSON(result)
    }
}

// MARK: - Hook Event Command

struct HookEventCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hook-event",
        abstract: "Forward a Claude Code hook event to the app (reads JSON from stdin)"
    )
    @Option(name: .long, help: "Session UUID") var session: String
    @Option(name: .long, help: "Event name (e.g., Stop, Notification, PreToolUse)") var event: String

    func run() throws {
        // Read JSON payload from stdin (Claude Code pipes event data here)
        var payload: [String: JSONValue] = [:]
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        if !stdinData.isEmpty {
            if let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: stdinData) {
                payload = parsed
            }
        }

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

// MARK: - Setup Command

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "setup", abstract: "First-time setup for Crow")

    @Option(name: .long, help: "Development root path") var devRoot: String?

    func run() throws {
        print("Welcome to Crow setup.\n")

        // Determine devRoot
        let root: String
        if let devRoot {
            root = devRoot
        } else {
            let defaultPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Dev").path
            print("Development root [\(defaultPath)]: ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                root = input
            } else {
                root = defaultPath
            }
        }

        // Create devRoot
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        print("  Using: \(root)\n")

        // Collect workspaces
        var workspaces: [[String: String]] = []
        var addMore = true

        while addMore {
            print("Add a workspace:")
            print("  Name: ", terminator: "")
            guard let name = readLine()?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                break
            }

            print("  Provider (github/gitlab) [github]: ", terminator: "")
            let providerInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            let provider = providerInput.isEmpty ? "github" : providerInput

            var host: String? = nil
            if provider == "gitlab" {
                print("  GitLab host (e.g., gitlab.example.com): ", terminator: "")
                let hostInput = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
                if !hostInput.isEmpty { host = hostInput }
            }

            workspaces.append(["name": name, "provider": provider, "host": host ?? ""])

            // Create workspace directory
            let wsPath = (root as NSString).appendingPathComponent(name)
            try FileManager.default.createDirectory(atPath: wsPath, withIntermediateDirectories: true)
            print("  Created: \(wsPath)")

            print("  Add another? (y/n) [n]: ", terminator: "")
            addMore = (readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "y")
            print()
        }

        // Build config JSON
        let wsEntries = workspaces.map { ws -> String in
            let hostField = ws["host"]!.isEmpty ? "null" : "\"\(ws["host"]!)\""
            let cli = ws["provider"] == "github" ? "gh" : "glab"
            return """
                {"name":"\(ws["name"]!)","provider":"\(ws["provider"]!)","cli":"\(cli)","host":\(hostField),"alwaysInclude":[]}
            """
        }
        let configJSON = """
        {
          "workspaces": [\(wsEntries.joined(separator: ","))],
          "defaults": {"provider":"github","cli":"gh","branchPrefix":"feature/","excludeDirs":["node_modules",".git","vendor","dist","build","target"]}
        }
        """

        // Write devRoot pointer
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("crow", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try root.write(to: appSupport.appendingPathComponent("devroot"), atomically: true, encoding: .utf8)

        // Scaffold .claude directory
        let claudeDir = (root as NSString).appendingPathComponent(".claude")
        let skillsDir = (claudeDir as NSString).appendingPathComponent("skills/crow-workspace")
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        // Write config
        let configPath = (claudeDir as NSString).appendingPathComponent("config.json")
        try configJSON.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Write CLAUDE.md (minimal version)
        let claudeMDPath = (claudeDir as NSString).appendingPathComponent("CLAUDE.md")
        if !FileManager.default.fileExists(atPath: claudeMDPath) {
            try "# Crow — Manager Context\n\nSee crow --help for CLI reference.\n\n## Known Issues / Corrections\n".write(
                toFile: claudeMDPath, atomically: true, encoding: .utf8)
        }

        print("Configuration saved to: \(configPath)")
        print("Workspace scaffolded at: \(claudeDir)/")
        print("\nLaunch Crow to get started.")
    }
}

