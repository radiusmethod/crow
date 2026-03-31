import AppKit
import Foundation
import RmCore
import RmPersistence
import RmTerminal

/// Simplified session service — CRUD only. Orchestration moved to Claude Code via ride CLI.
@MainActor
final class SessionService {
    private let store: JSONStore
    private let appState: AppState

    init(store: JSONStore, appState: AppState) {
        self.store = store
        self.appState = appState
    }

    // MARK: - Hydrate State from Store

    func hydrateState() {
        let data = store.data
        appState.sessions = data.sessions

        for session in data.sessions {
            appState.worktrees[session.id] = data.worktrees.filter { $0.sessionID == session.id }
            appState.links[session.id] = data.links.filter { $0.sessionID == session.id }

            // For work session terminals, clear the command so they start as plain shells.
            // We'll send `claude --continue` after the surfaces are created.
            var terminals = data.terminals.filter { $0.sessionID == session.id }
            if session.id != AppState.managerSessionID {
                for i in terminals.indices {
                    if let cmd = terminals[i].command, cmd.contains("claude") {
                        terminals[i] = SessionTerminal(
                            id: terminals[i].id,
                            sessionID: terminals[i].sessionID,
                            name: terminals[i].name,
                            cwd: terminals[i].cwd,
                            command: nil,  // Plain shell — claude --continue sent later
                            createdAt: terminals[i].createdAt
                        )
                    }
                }
            }
            appState.terminals[session.id] = terminals
        }
    }

    /// After the window is up, pre-create terminal surfaces off-screen,
    /// then send `claude --continue` to each work session terminal.
    func launchWorkSessionClaude(window: NSWindow) {
        let claudePath = Self.findClaudeBinary() ?? "claude"
        let workSessions = appState.sessions.filter { $0.id != AppState.managerSessionID && $0.status == .active }

        guard !workSessions.isEmpty else { return }

        // Step 1: Warm all terminal surfaces by briefly attaching them to the window off-screen.
        // This triggers viewDidMoveToWindow → createSurface without needing to select each tab.
        for session in workSessions {
            let terminals = appState.terminals(for: session.id)
            for terminal in terminals {
                TerminalManager.shared.warmSurface(
                    for: terminal.id,
                    workingDirectory: terminal.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path,
                    command: terminal.command,
                    in: window
                )
            }
        }

        // Step 2: After surfaces have initialized, send claude --continue to each
        let sendDelay = 3.0  // wait for surfaces to fully initialize
        for (i, session) in workSessions.enumerated() {
            let terminals = appState.terminals(for: session.id)
            for terminal in terminals {
                let delay = sendDelay + Double(i) * 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    TerminalManager.shared.send(id: terminal.id, text: "\(claudePath) --continue\n")
                }
            }
        }
    }

    // MARK: - Ensure Manager Session

    func ensureManagerSession(devRoot: String) {
        let managerID = AppState.managerSessionID
        if !appState.sessions.contains(where: { $0.id == managerID }) {
            let manager = Session(
                id: managerID,
                name: "Manager",
                status: .active
            )
            appState.sessions.insert(manager, at: 0)

            store.mutate { data in
                if !data.sessions.contains(where: { $0.id == managerID }) {
                    data.sessions.insert(manager, at: 0)
                }
            }
        }

        // Ensure manager has a terminal
        if appState.terminals(for: managerID).isEmpty {
            // Find the real claude binary (skip CMUX wrapper)
            let claudePath = Self.findClaudeBinary() ?? "claude"
            let terminal = SessionTerminal(
                sessionID: managerID,
                name: "Manager",
                cwd: devRoot,
                command: claudePath
            )
            appState.terminals[managerID] = [terminal]

            store.mutate { data in
                if !data.terminals.contains(where: { $0.sessionID == managerID }) {
                    data.terminals.append(terminal)
                }
            }
        }

        appState.selectedSessionID = managerID
    }

    // MARK: - Delete Session

    func deleteSession(id: UUID) async {
        guard id != AppState.managerSessionID else { return }

        let wts = appState.worktrees(for: id)
        let terminals = appState.terminals(for: id)

        // Destroy live terminal surfaces
        for terminal in terminals {
            TerminalManager.shared.destroy(id: terminal.id)
        }

        // Remove worktrees from disk: git worktree remove + branch delete
        // Skip cleanup for worktrees that point at the main repo checkout (not a real worktree)
        for wt in wts {
            let isMainCheckout = Self.isMainRepoCheckout(wt)

            if isMainCheckout {
                NSLog("Skipping worktree cleanup for main checkout: \(wt.worktreePath) (branch: \(wt.branch))")
                continue
            }

            do {
                // Remove the worktree
                let removeResult = try await shell("git", "-C", wt.repoPath, "worktree", "remove", "--force", wt.worktreePath)
                NSLog("Removed worktree: \(wt.worktreePath) \(removeResult)")

                // Delete the local branch (only if not a protected branch)
                if !Self.isProtectedBranch(wt.branch) {
                    _ = try? await shell("git", "-C", wt.repoPath, "branch", "-D", wt.branch)
                }

                // Prune worktree metadata
                _ = try? await shell("git", "-C", wt.repoPath, "worktree", "prune")

                // Remove the directory if it still exists
                try? FileManager.default.removeItem(atPath: wt.worktreePath)
            } catch {
                NSLog("Failed to remove worktree \(wt.worktreePath): \(error)")
                // Still try to remove the directory (but not if it's the main repo)
                try? FileManager.default.removeItem(atPath: wt.worktreePath)
            }
        }

        // Remove from state and persistence
        appState.sessions.removeAll { $0.id == id }
        appState.worktrees.removeValue(forKey: id)
        appState.links.removeValue(forKey: id)
        appState.terminals.removeValue(forKey: id)
        appState.activeTerminalID.removeValue(forKey: id)

        store.mutate { data in
            data.sessions.removeAll { $0.id == id }
            data.worktrees.removeAll { $0.sessionID == id }
            data.links.removeAll { $0.sessionID == id }
            data.terminals.removeAll { $0.sessionID == id }
        }

        if appState.selectedSessionID == id {
            appState.selectedSessionID = appState.sessions.first?.id
        }
    }

    // MARK: - Worktree Safety Checks

    /// Returns true if the worktree entry points at the main repo checkout (not a real git worktree).
    private static func isMainRepoCheckout(_ wt: SessionWorktree) -> Bool {
        // Normalize paths for comparison (resolve symlinks, trailing slashes)
        let worktree = (wt.worktreePath as NSString).standardizingPath
        let repo = (wt.repoPath as NSString).standardizingPath

        if worktree == repo { return true }
        if isProtectedBranch(wt.branch) { return true }

        return false
    }

    /// Returns true if a branch name is a protected default branch that should never be deleted.
    private static func isProtectedBranch(_ branch: String) -> Bool {
        let name = branch.lowercased()
        let protectedNames: Set<String> = ["main", "master", "develop", "dev", "trunk", "release"]
        return protectedNames.contains(name)
    }

    private func shell(_ args: String...) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Complete Session

    func completeSession(id: UUID) {
        guard id != AppState.managerSessionID else { return }

        if let idx = appState.sessions.firstIndex(where: { $0.id == id }) {
            appState.sessions[idx].status = .completed
            appState.sessions[idx].updatedAt = Date()
        }

        store.mutate { data in
            if let idx = data.sessions.firstIndex(where: { $0.id == id }) {
                data.sessions[idx].status = .completed
                data.sessions[idx].updatedAt = Date()
            }
        }
    }

    // MARK: - Persist Current State

    func persistState() {
        store.mutate { data in
            data.sessions = appState.sessions
            // Flatten worktrees, links, terminals from dicts
            data.worktrees = appState.worktrees.values.flatMap { $0 }
            data.links = appState.links.values.flatMap { $0 }
            data.terminals = appState.terminals.values.flatMap { $0 }
        }
    }

    // MARK: - Find Claude Binary

    /// Find the real claude binary, skipping CMUX wrapper.
    private static func findClaudeBinary() -> String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
