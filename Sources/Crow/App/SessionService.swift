import AppKit
import Foundation
import CrowCore
import CrowPersistence
import CrowTerminal

/// Simplified session service — CRUD only. Orchestration moved to Claude Code via crow CLI.
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

        // Backfill provider from ticketURL for sessions that predate provider tracking
        for i in appState.sessions.indices {
            if appState.sessions[i].provider == nil, let url = appState.sessions[i].ticketURL {
                appState.sessions[i].provider = Self.detectProviderFromURL(url)
            }
        }

        for session in appState.sessions {
            appState.worktrees[session.id] = data.worktrees.filter { $0.sessionID == session.id }
            appState.links[session.id] = data.links.filter { $0.sessionID == session.id }

            var terminals = data.terminals.filter { $0.sessionID == session.id }
            if session.id != AppState.managerSessionID {
                // Backward-compat migration: if no terminal is marked managed,
                // heuristically mark the first "Claude Code" terminal.
                let hasManagedTerminal = terminals.contains { $0.isManaged }
                if !hasManagedTerminal, let idx = terminals.firstIndex(where: {
                    $0.name == "Claude Code" || ($0.command?.contains("claude") ?? false)
                }) {
                    terminals[idx] = SessionTerminal(
                        id: terminals[idx].id, sessionID: terminals[idx].sessionID,
                        name: terminals[idx].name, cwd: terminals[idx].cwd,
                        command: terminals[idx].command, isManaged: true,
                        createdAt: terminals[idx].createdAt
                    )
                }

                // For managed terminals, clear the claude command so they start as plain shells.
                // We'll send `claude --continue` after the surfaces are created.
                for i in terminals.indices {
                    if terminals[i].isManaged,
                       let cmd = terminals[i].command, cmd.contains("claude") {
                        terminals[i] = SessionTerminal(
                            id: terminals[i].id, sessionID: terminals[i].sessionID,
                            name: terminals[i].name, cwd: terminals[i].cwd,
                            command: nil, isManaged: true,
                            createdAt: terminals[i].createdAt
                        )
                    }
                }
            }
            appState.terminals[session.id] = terminals

            // Initialize readiness tracking for managed work session terminals only
            if session.id != AppState.managerSessionID {
                for terminal in terminals where terminal.isManaged {
                    appState.terminalReadiness[terminal.id] = .uninitialized
                    TerminalManager.shared.trackReadiness(for: terminal.id)
                }
            }
        }
    }

    /// Wire TerminalManager readiness callbacks to update AppState.
    func wireTerminalReadiness() {
        NSLog("[SessionService] wireTerminalReadiness — setting onStateChanged callback")
        TerminalManager.shared.onStateChanged = { [weak self] terminalID, state in
            guard let self else { return }
            // Only update state for terminals we're tracking (work sessions, not Manager)
            guard self.appState.terminalReadiness[terminalID] != nil else { return }
            NSLog("[SessionService] onStateChanged: terminal=\(terminalID), state=\(state)")
            switch state {
            case .created:
                self.appState.terminalReadiness[terminalID] = .surfaceCreated
            case .shellReady:
                self.appState.terminalReadiness[terminalID] = .shellReady
            }
        }
    }

    /// Send `claude --continue` to a terminal and mark it as launched.
    func launchClaude(terminalID: UUID) {
        guard appState.terminalReadiness[terminalID] == .shellReady else { return }

        // Write/refresh hook config for the session's worktree
        if let sessionID = appState.terminals.first(where: { _, terminals in
            terminals.contains(where: { $0.id == terminalID })
        })?.key,
           let worktree = appState.primaryWorktree(for: sessionID),
           let crowPath = HookConfigGenerator.findCrowBinary() {
            try? HookConfigGenerator.writeHookConfig(
                worktreePath: worktree.worktreePath,
                sessionID: sessionID,
                crowPath: crowPath
            )
        }

        let claudePath = Self.findClaudeBinary() ?? "claude"
        TerminalManager.shared.send(id: terminalID, text: "\(claudePath) --continue\n")
        appState.terminalReadiness[terminalID] = .claudeLaunched
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

        // Select Manager on launch (selectedSessionID isn't persisted)
        if appState.selectedSessionID == nil {
            appState.selectedSessionID = managerID
        }
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

            // Remove our hook config from settings.local.json before deleting the worktree
            HookConfigGenerator.removeHookConfig(worktreePath: wt.worktreePath)

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
        appState.removeHookState(for: id)

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

    // MARK: - Provider Detection

    /// Detect provider from a ticket URL without hardcoding specific hosts.
    static func detectProviderFromURL(_ url: String) -> Provider? {
        if url.contains("github.com") {
            return .github
        } else if url.contains("gitlab.com") || url.contains("gitlab") || url.contains("/-/issues") || url.contains("/-/merge_requests") {
            return .gitlab
        }
        return nil
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
        let name = branch
            .replacingOccurrences(of: "refs/heads/", with: "")
            .replacingOccurrences(of: "origin/", with: "")
            .lowercased()
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

    /// Resolve org/repo slug from a repo's git remote URL.
    private func resolveRepoSlug(repoPath: String) -> String? {
        guard let output = try? shellSync("git", "-C", repoPath, "remote", "get-url", "origin") else { return nil }
        var url = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
        if let match = url.range(of: #"[:/]([^/:]+/[^/:]+)$"#, options: .regularExpression) {
            return String(url[match]).trimmingCharacters(in: CharacterSet(charactersIn: "/:"))
        }
        return nil
    }

    private func shellSync(_ args: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SessionService", code: Int(process.terminationStatus))
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Orphan Worktree Detection

    /// Scan repos for worktrees that exist on disk but have no session in the store.
    /// Re-imports them as active sessions so they appear in the sidebar.
    func detectOrphanedWorktrees() async {
        guard let devRoot = ConfigStore.loadDevRoot(),
              let config = ConfigStore.loadConfig(devRoot: devRoot) else { return }

        // Save current selection so orphan mutations don't reset it
        let savedSelection = appState.selectedSessionID

        // Collect all known worktree paths from the store
        let knownPaths = Set(
            appState.worktrees.values.flatMap { $0 }
                .map { ($0.worktreePath as NSString).standardizingPath }
        )

        let fm = FileManager.default

        // Scan each workspace for repos
        guard let workspaceDirs = try? fm.contentsOfDirectory(atPath: devRoot) else { return }

        for wsDir in workspaceDirs {
            let wsPath = (devRoot as NSString).appendingPathComponent(wsDir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: wsPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard !config.defaults.excludeDirs.contains(wsDir) else { continue }

            guard let repoDirs = try? fm.contentsOfDirectory(atPath: wsPath) else { continue }
            for repoDir in repoDirs {
                let repoPath = (wsPath as NSString).appendingPathComponent(repoDir)
                let gitPath = (repoPath as NSString).appendingPathComponent(".git")
                var gitIsDir: ObjCBool = false

                // Only process real repos (not worktrees — .git is a directory for repos, a file for worktrees)
                guard fm.fileExists(atPath: gitPath, isDirectory: &gitIsDir), gitIsDir.boolValue else { continue }

                // Get worktrees for this repo
                guard let output = try? await shell("git", "-C", repoPath, "worktree", "list", "--porcelain") else { continue }
                let worktrees = parseWorktreeList(output)

                for wt in worktrees {
                    let standardPath = (wt.path as NSString).standardizingPath

                    // Skip the main checkout
                    if standardPath == (repoPath as NSString).standardizingPath { continue }

                    // Skip if already tracked
                    if knownPaths.contains(standardPath) { continue }

                    // Skip protected branches
                    if Self.isProtectedBranch(wt.branch) { continue }

                    // This is an orphan — recover it
                    NSLog("[SessionService] Recovered orphan worktree: \(wt.path) branch=\(wt.branch)")
                    await recoverOrphan(worktreePath: wt.path, branch: wt.branch, repoName: repoDir, repoPath: repoPath, workspace: wsDir)
                }
            }
        }

        // Restore selection if orphan mutations reset it
        if savedSelection != nil && appState.selectedSessionID != savedSelection {
            appState.selectedSessionID = savedSelection
        }
    }

    private struct WorktreeEntry {
        let path: String
        let branch: String
    }

    private func parseWorktreeList(_ output: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                // Save previous entry
                if let path = currentPath, let branch = currentBranch {
                    entries.append(WorktreeEntry(path: path, branch: branch))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
            } else if line.hasPrefix("branch ") {
                currentBranch = String(line.dropFirst("branch ".count))
                    .replacingOccurrences(of: "refs/heads/", with: "")
            }
        }
        // Don't forget the last entry
        if let path = currentPath, let branch = currentBranch {
            entries.append(WorktreeEntry(path: path, branch: branch))
        }
        return entries
    }

    private func recoverOrphan(worktreePath: String, branch: String, repoName: String, repoPath: String, workspace: String) async {
        let dirName = (worktreePath as NSString).lastPathComponent

        // Try to parse ticket number from directory name (e.g., "citadel-209-slug" → 209)
        var ticketNumber: Int?
        var ticketURL: String?
        var ticketTitle: String?
        var provider: Provider?

        let parts = dirName.components(separatedBy: "-")
        // Look for a numeric part after the repo name prefix
        if let repoPrefix = parts.first {
            for (i, part) in parts.enumerated() where i > 0 {
                if let num = Int(part) {
                    ticketNumber = num
                    break
                }
            }
        }

        // Try to construct ticket URL and fetch title from GitHub
        if let num = ticketNumber {
            if let remoteURL = try? await shell("git", "-C", repoPath, "remote", "get-url", "origin") {
                var url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
                // Convert SSH to HTTPS
                if url.hasPrefix("git@github.com:") {
                    let slug = url.replacingOccurrences(of: "git@github.com:", with: "")
                    ticketURL = "https://github.com/\(slug)/issues/\(num)"
                    provider = .github
                } else if url.contains("github.com") {
                    ticketURL = "\(url)/issues/\(num)"
                    provider = .github
                }
            }

            // Try to fetch issue title
            if let issueURL = ticketURL {
                if let output = try? await shell("gh", "issue", "view", issueURL, "--json", "title"),
                   let data = output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String {
                    ticketTitle = title
                }
            }
        }

        // Create the session
        let session = Session(
            name: dirName,
            status: .active,
            ticketURL: ticketURL,
            ticketTitle: ticketTitle,
            ticketNumber: ticketNumber,
            provider: provider
        )

        let worktree = SessionWorktree(
            sessionID: session.id,
            repoName: repoName,
            repoPath: repoPath,
            worktreePath: worktreePath,
            branch: branch,
            workspace: workspace,
            isPrimary: true
        )

        let terminal = SessionTerminal(
            sessionID: session.id,
            name: "Claude Code",
            cwd: worktreePath,
            isManaged: true
        )

        // Add to state and store
        appState.sessions.append(session)
        appState.worktrees[session.id] = [worktree]
        appState.terminals[session.id] = [terminal]
        appState.terminalReadiness[terminal.id] = .uninitialized
        TerminalManager.shared.trackReadiness(for: terminal.id)

        if let ticketURL {
            let link = SessionLink(sessionID: session.id, label: "Issue #\(ticketNumber ?? 0)", url: ticketURL, linkType: .ticket)
            appState.links[session.id] = [link]
            store.mutate { data in
                data.links.append(link)
            }
        }

        // Check for a PR on this branch
        if let repoSlug = resolveRepoSlug(repoPath: repoPath) {
            if let prOutput = try? await shell(
                "gh", "pr", "list", "--repo", repoSlug, "--head", branch,
                "--state", "all", "--json", "number,url,state", "--limit", "1"
            ), let prData = prOutput.data(using: .utf8),
               let prItems = try? JSONSerialization.jsonObject(with: prData) as? [[String: Any]],
               let pr = prItems.first,
               let prNum = pr["number"] as? Int,
               let prURL = pr["url"] as? String {
                let prLink = SessionLink(sessionID: session.id, label: "PR #\(prNum)", url: prURL, linkType: .pr)
                appState.links[session.id, default: []].append(prLink)
                store.mutate { data in
                    data.links.append(prLink)
                }
                NSLog("[SessionService] Found PR #\(prNum) for orphan '\(dirName)'")
            }
        }

        store.mutate { data in
            data.sessions.append(session)
            data.worktrees.append(worktree)
            data.terminals.append(terminal)
        }

        NSLog("[SessionService] Recovered session '\(dirName)' — ticket=#\(ticketNumber ?? 0) title=\(ticketTitle ?? "unknown")")
    }

    // MARK: - Terminal Tab Management

    /// Add a new plain-shell terminal tab to a session.
    func addTerminal(sessionID: UUID) {
        let cwd = appState.primaryWorktree(for: sessionID)?.worktreePath
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let terminal = SessionTerminal(
            sessionID: sessionID, name: "Shell", cwd: cwd, isManaged: false
        )
        appState.terminals[sessionID, default: []].append(terminal)
        appState.activeTerminalID[sessionID] = terminal.id
        store.mutate { data in data.terminals.append(terminal) }
    }

    /// Close a non-managed terminal tab.
    func closeTerminal(sessionID: UUID, terminalID: UUID) {
        guard let terminals = appState.terminals[sessionID],
              let terminal = terminals.first(where: { $0.id == terminalID }),
              !terminal.isManaged else { return }

        TerminalManager.shared.destroy(id: terminalID)
        appState.terminals[sessionID]?.removeAll { $0.id == terminalID }
        appState.terminalReadiness.removeValue(forKey: terminalID)

        if appState.activeTerminalID[sessionID] == terminalID {
            appState.activeTerminalID[sessionID] = appState.terminals[sessionID]?.first?.id
        }

        store.mutate { data in data.terminals.removeAll { $0.id == terminalID } }
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

    func setSessionInReview(id: UUID) {
        guard id != AppState.managerSessionID else { return }

        if let idx = appState.sessions.firstIndex(where: { $0.id == id }) {
            appState.sessions[idx].status = .inReview
            appState.sessions[idx].updatedAt = Date()
        }

        store.mutate { data in
            if let idx = data.sessions.firstIndex(where: { $0.id == id }) {
                data.sessions[idx].status = .inReview
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

    // MARK: - VS Code Integration

    /// Find the VS Code `code` CLI binary.
    static func findVSCodeBinary() -> String? {
        let candidates = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/code").path,
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Check if VS Code CLI is available and cache the result in AppState.
    func detectVSCode() {
        appState.vsCodeAvailable = Self.findVSCodeBinary() != nil
    }

    /// Open the primary worktree for a session in VS Code.
    func openInVSCode(sessionID: UUID) {
        guard let codePath = Self.findVSCodeBinary() else { return }
        guard let wt = appState.primaryWorktree(for: sessionID) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codePath)
        process.arguments = [wt.worktreePath]
        try? process.run()
    }

    /// Open a terminal window at the primary worktree path for a session.
    func openTerminal(sessionID: UUID) {
        guard let wt = appState.primaryWorktree(for: sessionID) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", wt.worktreePath]
        try? process.run()
    }
}
