import AppKit
import SwiftUI
import CrowCore
import CrowUI
import CrowPersistence
import CrowTerminal
import CrowIPC

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private let appState = AppState()
    private var store: JSONStore?
    private var sessionService: SessionService?
    private var socketServer: SocketServer?
    private var issueTracker: IssueTracker?
    private var notificationManager: NotificationManager?
    private var allowListService: AllowListService?
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
        window.title = "Crow Setup"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeSetup(devRoot: String, config: AppConfig) -> String? {
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
            return nil
        } catch {
            NSLog("[Crow] Setup failed: %@", error.localizedDescription)
            return "Setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Main App Launch

    private func launchMainApp() {
        guard let devRoot else { return }

        // Initialize libghostty
        NSLog("[Crow] Initializing Ghostty")
        GhosttyApp.shared.initialize()

        // Load config
        let config = appConfig ?? ConfigStore.loadConfig(devRoot: devRoot) ?? AppConfig()
        self.appConfig = config
        NSLog("[Crow] Config loaded (workspaces: %d)", config.workspaces.count)

        // Update skills and CLAUDE.md on every launch
        let scaffolder = Scaffolder(devRoot: devRoot)
        do {
            try scaffolder.scaffold(workspaceNames: config.workspaces.map(\.name))
        } catch {
            NSLog("[Crow] Scaffold update failed: %@", error.localizedDescription)
        }

        // Initialize persistence
        let store = JSONStore()
        self.store = store

        // Create session service and hydrate state
        let service = SessionService(store: store, appState: appState)
        service.hydrateState()
        self.sessionService = service
        NSLog("[Crow] Session state hydrated (%d sessions)", appState.sessions.count)

        // Detect orphaned worktrees (runs async, updates UI when done)
        Task { await service.detectOrphanedWorktrees() }

        // Check for runtime dependencies (non-blocking)
        Task {
            let missing = await Task.detached {
                let tools = ["gh", "git", "claude", "glab", "code"]
                return tools.filter { !ShellEnvironment.shared.hasCommand($0) }
            }.value
            if !missing.isEmpty {
                for tool in missing {
                    NSLog("[Crow] Runtime dependency not found: %@", tool)
                }
                appState.missingDependencies = missing
            }
        }

        // Ensure manager session exists
        service.ensureManagerSession(devRoot: devRoot)

        // Wire closures for UI actions
        appState.onDeleteSession = { [weak self, weak service] id in
            self?.notificationManager?.clearSession(id)
            await service?.deleteSession(id: id)
        }
        appState.onCompleteSession = { [weak service] id in
            service?.completeSession(id: id)
        }
        appState.onSetSessionInReview = { [weak service] id in
            service?.setSessionInReview(id: id)
        }

        appState.onLaunchClaude = { [weak service] terminalID in
            service?.launchClaude(terminalID: terminalID)
        }

        // Wire terminal tab management
        appState.onAddTerminal = { [weak service] sessionID in
            service?.addTerminal(sessionID: sessionID)
        }
        appState.onCloseTerminal = { [weak service] sessionID, terminalID in
            service?.closeTerminal(sessionID: sessionID, terminalID: terminalID)
        }
        appState.onAddGlobalTerminal = { [weak service] in
            service?.addGlobalTerminal()
        }
        appState.onCloseGlobalTerminal = { [weak service] terminalID in
            service?.closeGlobalTerminal(terminalID: terminalID)
        }

        // Detect VS Code CLI and wire open action
        service.detectVSCode()
        appState.onOpenInVSCode = { [weak service] sessionID in
            service?.openInVSCode(sessionID: sessionID)
        }

        // Wire open terminal action
        appState.onOpenTerminal = { [weak service] sessionID in
            service?.openTerminal(sessionID: sessionID)
        }

        // Wire "Work on" issue action — sends issue URL to Manager terminal
        appState.onWorkOnIssue = { [weak self] issueURL in
            guard let self, let managerTerminals = self.appState.terminals[AppState.managerSessionID],
                  let managerTerminal = managerTerminals.first else { return }
            // Type the /crow-workspace command into the Manager terminal
            TerminalManager.shared.send(
                id: managerTerminal.id,
                text: "/crow-workspace \(issueURL)\n"
            )
            // Switch to Manager tab
            self.appState.selectedSessionID = AppState.managerSessionID
        }

        // Wire "Start Review" action — creates review session for a PR
        appState.onStartReview = { [weak self] prURL in
            guard let self else { return }
            Task { await self.sessionService?.createReviewSession(prURL: prURL) }
        }

        // Start issue tracker
        let tracker = IssueTracker(appState: appState)
        tracker.onNewReviewRequests = { [weak self] newRequests in
            for request in newRequests {
                self?.notificationManager?.notifyReviewRequest(request)
            }
        }
        tracker.start()
        self.issueTracker = tracker

        appState.onMarkInReview = { [weak tracker] id in
            Task { await tracker?.markInReview(sessionID: id) }
        }

        // Initialize notification manager
        let notifManager = NotificationManager(appState: appState, settings: config.notifications)
        self.notificationManager = notifManager

        // Initialize allow list service
        let allowList = AllowListService(appState: appState, devRoot: devRoot)
        self.allowListService = allowList
        appState.onLoadAllowList = { [weak allowList] in
            allowList?.scan()
        }
        appState.onPromoteToGlobal = { [weak allowList] patterns in
            allowList?.promoteToGlobal(patterns: patterns)
        }

        // Hydrate mute state from config and wire toggle
        appState.soundMuted = config.notifications.globalMute
        appState.hideSessionDetails = config.sidebar.hideSessionDetails
        appState.onSoundMutedChanged = { [weak self] muted in
            self?.appConfig?.notifications.globalMute = muted
            if let settings = self?.appConfig?.notifications {
                self?.notificationManager?.updateSettings(settings)
            }
            if let devRoot = self?.devRoot, let cfg = self?.appConfig {
                try? ConfigStore.saveConfig(cfg, devRoot: devRoot)
            }
        }

        // Start socket server
        startSocketServer(store: store, devRoot: devRoot, sessionService: service)

        NSLog("[Crow] Main app launch complete — creating window")

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
        mainWindow.title = "Crow"
        mainWindow.minSize = NSSize(width: 800, height: 500)
        mainWindow.contentView = hostingView
        mainWindow.center()
        // Set autosave name after center() so a saved frame takes precedence
        mainWindow.setFrameAutosaveName("MainWindow")
        mainWindow.makeKeyAndOrderFront(nil)
        self.window = mainWindow

        // Set up Settings menu item
        setupMenu()

        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Crow", action: #selector(showAbout), keyEquivalent: "")
        appMenu.items.last?.target = self
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Crow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Crow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: AboutView())
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "About Crow"
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        win.contentView = hostingView
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.aboutWindow = win
    }

    @objc private func showSettings() {
        guard let devRoot, let appConfig else { return }

        if let existing = settingsWindow {
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        win.contentView = hostingView
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.settingsWindow = win
    }

    private func saveSettings(devRoot: String, config: AppConfig) {
        self.devRoot = devRoot
        self.appConfig = config
        do {
            try ConfigStore.saveDevRoot(devRoot)
        } catch {
            NSLog("[Crow] Failed to save devRoot: %@", error.localizedDescription)
        }
        do {
            try ConfigStore.saveConfig(config, devRoot: devRoot)
        } catch {
            NSLog("[Crow] Failed to save config: %@", error.localizedDescription)
        }
        notificationManager?.updateSettings(config.notifications)
        appState.hideSessionDetails = config.sidebar.hideSessionDetails
    }

    // MARK: - Socket Server

    private func startSocketServer(store: JSONStore, devRoot: String, sessionService: SessionService) {
        var handlers: [String: CommandRouter.Handler] = [:]
        handlers.merge(sessionHandlers(appState: appState, store: store, service: sessionService)) { _, n in n }
        handlers.merge(worktreeHandlers(appState: appState, store: store, devRoot: devRoot)) { _, n in n }
        handlers.merge(terminalHandlers(appState: appState, store: store, devRoot: devRoot)) { _, n in n }
        handlers.merge(linkHandlers(appState: appState, store: store)) { _, n in n }
        handlers.merge(hookHandlers(appState: appState, notifManager: notificationManager)) { _, n in n }

        let router = CommandRouter(handlers: handlers)
        let server = SocketServer(router: router)
        do {
            try server.start()
            self.socketServer = server
            NSLog("crow socket server started at: \(server.path)")
        } catch {
            NSLog("Failed to start socket server: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("[Crow] Application terminating — beginning cleanup")
        issueTracker?.stop()
        sessionService?.persistState()
        // Persist config in case settings changed during this session
        if let devRoot, let appConfig {
            try? ConfigStore.saveConfig(appConfig, devRoot: devRoot)
        }
        socketServer?.stop()
        GhosttyApp.shared.shutdown()
        NSLog("[Crow] Cleanup complete")
    }

    // MARK: - Claude Binary Resolution

    /// Replace bare `claude` in a command string with the full path to the real binary,
    /// skipping the CMUX wrapper.
    nonisolated static func resolveClaudeInCommand(_ command: String) -> String {
        for path in SessionService.claudeBinaryCandidates {
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
