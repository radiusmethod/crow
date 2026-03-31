import AppKit
import SwiftUI
import RmCore
import RmUI
import RmPersistence
import RmTerminal
import RmIPC

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private let appState = AppState()
    private var store: JSONStore?
    private var sessionService: SessionService?
    private var socketServer: SocketServer?
    private var issueTracker: IssueTracker?
    private var devRoot: String?
    private var appConfig: AppConfig?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for devRoot pointer
        if let root = ConfigStore.loadDevRoot() {
            devRoot = root
            launchMainApp()
        } else {
            showSetupWizard()
        }
    }

    // MARK: - Setup Wizard

    private func showSetupWizard() {
        var wizardView = SetupWizardView()
        wizardView.onComplete = { [weak self] devRoot, config in
            self?.completeSetup(devRoot: devRoot, config: config)
        }
        wizardView.onImportCMUX = {
            ConfigStore.importFromCMUX()
        }

        let hostingView = NSHostingView(rootView: wizardView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "rm-ai-ide Setup"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeSetup(devRoot: String, config: AppConfig) {
        do {
            // Save devRoot pointer
            try ConfigStore.saveDevRoot(devRoot)

            // Scaffold directory structure
            let scaffolder = Scaffolder(devRoot: devRoot)
            try scaffolder.scaffold(workspaceNames: config.workspaces.map(\.name))

            // Save config
            try ConfigStore.saveConfig(config, devRoot: devRoot)

            // Now launch normally
            self.devRoot = devRoot
            self.appConfig = config
            launchMainApp()
        } catch {
            NSLog("Setup failed: \(error)")
        }
    }

    // MARK: - Main App Launch

    private func launchMainApp() {
        guard let devRoot else { return }

        // Initialize libghostty
        GhosttyApp.shared.initialize()

        // Load config
        let config = appConfig ?? ConfigStore.loadConfig(devRoot: devRoot) ?? AppConfig()
        self.appConfig = config

        // Update skills and CLAUDE.md on every launch
        let scaffolder = Scaffolder(devRoot: devRoot)
        try? scaffolder.scaffold(workspaceNames: config.workspaces.map(\.name))

        // Initialize persistence
        let store = JSONStore()
        self.store = store

        // Create session service and hydrate state
        let service = SessionService(store: store, appState: appState)
        service.hydrateState()
        self.sessionService = service

        // Ensure manager session exists
        service.ensureManagerSession(devRoot: devRoot)

        // Wire closures for UI actions
        appState.onDeleteSession = { [weak service] id in
            await service?.deleteSession(id: id)
        }
        appState.onCompleteSession = { [weak service] id in
            service?.completeSession(id: id)
        }

        // Wire "Work on" issue action — sends issue URL to Manager terminal
        appState.onWorkOnIssue = { [weak self] issueURL in
            guard let self, let managerTerminals = self.appState.terminals[AppState.managerSessionID],
                  let managerTerminal = managerTerminals.first else { return }
            // Type the /ride-workspace command into the Manager terminal
            TerminalManager.shared.send(
                id: managerTerminal.id,
                text: "/ride-workspace \(issueURL)\n"
            )
            // Switch to Manager tab
            self.appState.selectedSessionID = AppState.managerSessionID
        }

        // Start issue tracker
        let tracker = IssueTracker(appState: appState)
        tracker.start()
        self.issueTracker = tracker

        // Start socket server
        startSocketServer(store: store, devRoot: devRoot)

        // Create main window
        let contentView = MainContentView(appState: appState)
        let hostingView = NSHostingView(rootView: contentView)

        // Close wizard window if it exists, create main window
        window?.close()

        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "rm-ai-ide"
        mainWindow.contentView = hostingView
        mainWindow.center()
        mainWindow.setFrameAutosaveName("MainWindow")
        mainWindow.makeKeyAndOrderFront(nil)
        self.window = mainWindow

        // Set up Settings menu item
        setupMenu()

        NSApp.activate(ignoringOtherApps: true)

        // After the window is fully up, pre-create terminal surfaces
        // and launch `claude --continue` in each
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, let window = self.window else { return }
            self.sessionService?.launchWorkSessionClaude(window: window)
        }
    }

    // MARK: - Settings

    private func setupMenu() {
        // The Settings menu item is handled by the system when we implement
        // the settings window. For now, we can add a manual menu item.
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
            let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
            settingsItem.target = self
            appMenu.insertItem(settingsItem, at: 2)
            appMenu.insertItem(NSMenuItem.separator(), at: 3)
        }
    }

    @objc private func showSettings() {
        guard let devRoot, let appConfig else { return }

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(
            devRoot: devRoot,
            config: appConfig,
            onSave: { [weak self] newDevRoot, newConfig in
                self?.saveSettings(devRoot: newDevRoot, config: newConfig)
            },
            onRescaffold: { [weak self] devRoot in
                let scaffolder = Scaffolder(devRoot: devRoot)
                try? scaffolder.scaffold(workspaceNames: self?.appConfig?.workspaces.map(\.name) ?? [])
            }
        )

        let hostingView = NSHostingView(rootView: settingsView)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.contentView = hostingView
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.settingsWindow = win
    }

    private func saveSettings(devRoot: String, config: AppConfig) {
        self.devRoot = devRoot
        self.appConfig = config
        try? ConfigStore.saveDevRoot(devRoot)
        try? ConfigStore.saveConfig(config, devRoot: devRoot)
    }

    // MARK: - Socket Server

    private func startSocketServer(store: JSONStore, devRoot: String) {
        let capturedAppState = appState
        let capturedStore = store

        let router = CommandRouter(handlers: [
            "new-session": { @Sendable params in
                let name = params["name"]?.stringValue ?? "untitled"
                return await MainActor.run {
                    let session = Session(name: name)
                    capturedAppState.sessions.append(session)
                    capturedStore.mutate { $0.sessions.append(session) }
                    return ["session_id": .string(session.id.uuidString), "name": .string(session.name)]
                }
            },
            "rename-session": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue,
                      let id = UUID(uuidString: idStr),
                      let name = params["name"]?.stringValue else {
                    throw RPCError.invalidParams("session_id and name required")
                }
                return await MainActor.run {
                    if let idx = capturedAppState.sessions.firstIndex(where: { $0.id == id }) {
                        capturedAppState.sessions[idx].name = name
                        capturedStore.mutate { data in
                            if let i = data.sessions.firstIndex(where: { $0.id == id }) { data.sessions[i].name = name }
                        }
                    }
                    return ["session_id": .string(idStr), "name": .string(name)]
                }
            },
            "select-session": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue,
                      let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                await MainActor.run { capturedAppState.selectedSessionID = id }
                return ["session_id": .string(idStr)]
            },
            "list-sessions": { @Sendable _ in
                let sessions = await MainActor.run { capturedAppState.sessions }
                let items: [JSONValue] = sessions.map { s in
                    .object(["id": .string(s.id.uuidString), "name": .string(s.name), "status": .string(s.status.rawValue)])
                }
                return ["sessions": .array(items)]
            },
            "get-session": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                return await MainActor.run {
                    guard let s = capturedAppState.sessions.first(where: { $0.id == id }) else {
                        return ["error": .string("Session not found")]
                    }
                    return ["id": .string(s.id.uuidString), "name": .string(s.name), "status": .string(s.status.rawValue),
                            "ticket_url": s.ticketURL.map { .string($0) } ?? .null, "ticket_title": s.ticketTitle.map { .string($0) } ?? .null]
                }
            },
            "set-status": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr),
                      let statusStr = params["status"]?.stringValue, let status = SessionStatus(rawValue: statusStr) else {
                    throw RPCError.invalidParams("session_id and status required")
                }
                return await MainActor.run {
                    if let idx = capturedAppState.sessions.firstIndex(where: { $0.id == id }) {
                        capturedAppState.sessions[idx].status = status
                        capturedStore.mutate { data in
                            if let i = data.sessions.firstIndex(where: { $0.id == id }) { data.sessions[i].status = status }
                        }
                    }
                    return ["session_id": .string(idStr), "status": .string(statusStr)]
                }
            },
            "delete-session": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                guard id != AppState.managerSessionID else { throw RPCError.applicationError("Cannot delete manager session") }
                await MainActor.run {
                    capturedAppState.sessions.removeAll { $0.id == id }
                    capturedAppState.worktrees.removeValue(forKey: id)
                    capturedAppState.links.removeValue(forKey: id)
                    capturedAppState.terminals.removeValue(forKey: id)
                    capturedStore.mutate { data in
                        data.sessions.removeAll { $0.id == id }; data.worktrees.removeAll { $0.sessionID == id }
                        data.links.removeAll { $0.sessionID == id }; data.terminals.removeAll { $0.sessionID == id }
                    }
                    if capturedAppState.selectedSessionID == id { capturedAppState.selectedSessionID = capturedAppState.sessions.first?.id }
                }
                return ["deleted": .bool(true)]
            },
            "set-ticket": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                return await MainActor.run {
                    if let idx = capturedAppState.sessions.firstIndex(where: { $0.id == id }) {
                        if let url = params["url"]?.stringValue { capturedAppState.sessions[idx].ticketURL = url }
                        if let title = params["title"]?.stringValue { capturedAppState.sessions[idx].ticketTitle = title }
                        if let num = params["number"]?.intValue { capturedAppState.sessions[idx].ticketNumber = num }
                        capturedStore.mutate { data in
                            if let i = data.sessions.firstIndex(where: { $0.id == id }) { data.sessions[i] = capturedAppState.sessions[idx] }
                        }
                    }
                    return ["session_id": .string(idStr)]
                }
            },
            "add-worktree": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let sessionID = UUID(uuidString: idStr),
                      let repo = params["repo"]?.stringValue, let path = params["path"]?.stringValue,
                      let branch = params["branch"]?.stringValue else {
                    throw RPCError.invalidParams("session_id, repo, path, branch required")
                }
                // repo_path is the main repo (for git commands). Defaults to path if not provided.
                let repoPath = params["repo_path"]?.stringValue ?? path
                let wt = SessionWorktree(sessionID: sessionID, repoName: repo, repoPath: repoPath, worktreePath: path,
                                         branch: branch, workspace: params["workspace"]?.stringValue ?? "",
                                         isPrimary: params["primary"]?.boolValue ?? false)
                return await MainActor.run {
                    capturedAppState.worktrees[sessionID, default: []].append(wt)
                    capturedStore.mutate { $0.worktrees.append(wt) }
                    return ["worktree_id": .string(wt.id.uuidString), "session_id": .string(idStr), "path": .string(path)]
                }
            },
            "list-worktrees": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                let wts = await MainActor.run { capturedAppState.worktrees(for: id) }
                let items: [JSONValue] = wts.map { wt in
                    .object(["id": .string(wt.id.uuidString), "repo": .string(wt.repoName), "path": .string(wt.worktreePath),
                             "branch": .string(wt.branch), "primary": .bool(wt.isPrimary)])
                }
                return ["worktrees": .array(items)]
            },
            "new-terminal": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let sessionID = UUID(uuidString: idStr),
                      let cwd = params["cwd"]?.stringValue else {
                    throw RPCError.invalidParams("session_id and cwd required")
                }
                // Resolve claude binary path if command references claude
                var command = params["command"]?.stringValue
                if let cmd = command, cmd.contains("claude") {
                    command = AppDelegate.resolveClaudeInCommand(cmd)
                }
                let terminal = SessionTerminal(sessionID: sessionID, name: params["name"]?.stringValue ?? "Shell",
                                               cwd: cwd, command: command)
                return await MainActor.run {
                    capturedAppState.terminals[sessionID, default: []].append(terminal)
                    capturedStore.mutate { $0.terminals.append(terminal) }
                    return ["terminal_id": .string(terminal.id.uuidString), "session_id": .string(idStr)]
                }
            },
            "list-terminals": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                let terms = await MainActor.run { capturedAppState.terminals(for: id) }
                let items: [JSONValue] = terms.map { t in
                    .object(["id": .string(t.id.uuidString), "name": .string(t.name), "session_id": .string(t.sessionID.uuidString)])
                }
                return ["terminals": .array(items)]
            },
            "send": { @Sendable params in
                guard let sessionIDStr = params["session_id"]?.stringValue,
                      let sessionID = UUID(uuidString: sessionIDStr),
                      let terminalIDStr = params["terminal_id"]?.stringValue,
                      let terminalID = UUID(uuidString: terminalIDStr),
                      var text = params["text"]?.stringValue else {
                    throw RPCError.invalidParams("session_id, terminal_id, and text required")
                }
                // Process escape sequences: literal \n in the text becomes a real newline
                text = text.replacingOccurrences(of: "\\n", with: "\n")
                text = text.replacingOccurrences(of: "\\t", with: "\t")
                NSLog("ride send: text length=\(text.count), ends_with_newline=\(text.hasSuffix("\n")), ends_with_cr=\(text.hasSuffix("\r"))")
                await MainActor.run {
                    // If the surface doesn't exist yet, create it from stored terminal data
                    if TerminalManager.shared.existingSurface(for: terminalID) == nil {
                        if let terminals = capturedAppState.terminals[sessionID],
                           let terminal = terminals.first(where: { $0.id == terminalID }) {
                            _ = TerminalManager.shared.surface(
                                for: terminalID,
                                workingDirectory: terminal.cwd,
                                command: terminal.command
                            )
                        }
                    }
                    TerminalManager.shared.send(id: terminalID, text: text)
                }
                return ["sent": .bool(true)]
            },
            "add-link": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let sessionID = UUID(uuidString: idStr),
                      let label = params["label"]?.stringValue, let url = params["url"]?.stringValue else {
                    throw RPCError.invalidParams("session_id, label, url required")
                }
                let link = SessionLink(sessionID: sessionID, label: label, url: url,
                                       linkType: LinkType(rawValue: params["type"]?.stringValue ?? "custom") ?? .custom)
                return await MainActor.run {
                    capturedAppState.links[sessionID, default: []].append(link)
                    capturedStore.mutate { $0.links.append(link) }
                    return ["link_id": .string(link.id.uuidString)]
                }
            },
            "list-links": { @Sendable params in
                guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                    throw RPCError.invalidParams("session_id required")
                }
                let lnks = await MainActor.run { capturedAppState.links(for: id) }
                let items: [JSONValue] = lnks.map { l in
                    .object(["id": .string(l.id.uuidString), "label": .string(l.label), "url": .string(l.url), "type": .string(l.linkType.rawValue)])
                }
                return ["links": .array(items)]
            },
        ])

        let server = SocketServer(router: router)
        do {
            try server.start()
            self.socketServer = server
            NSLog("ride socket server started at: \(server.path)")
        } catch {
            NSLog("Failed to start socket server: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        issueTracker?.stop()
        sessionService?.persistState()
        socketServer?.stop()
        GhosttyApp.shared.shutdown()
    }

    // MARK: - Claude Binary Resolution

    /// Replace bare `claude` in a command string with the full path to the real binary,
    /// skipping the CMUX wrapper.
    nonisolated static func resolveClaudeInCommand(_ command: String) -> String {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                // Replace "claude" at word boundaries with the full path
                // Handle: "claude ...", "claude", "/path/to/claude ..."
                var result = command
                // If command starts with bare "claude" (not already a path)
                if result.hasPrefix("claude ") || result == "claude" {
                    result = path + result.dropFirst(6)
                }
                return result
            }
        }
        return command
    }
}

enum RPCError: Error, LocalizedError {
    case invalidParams(String)
    case applicationError(String)
    var errorDescription: String? {
        switch self {
        case .invalidParams(let msg): msg
        case .applicationError(let msg): msg
        }
    }
}
