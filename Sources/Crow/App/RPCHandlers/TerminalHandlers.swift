import CrowCore
import CrowIPC
import CrowPersistence
import CrowTerminal
import Foundation

func terminalHandlers(
    appState: AppState,
    store: JSONStore,
    devRoot: String
) -> [String: CommandRouter.Handler] {
    [
        "new-terminal": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let sessionID = UUID(uuidString: idStr),
                  let cwd = params["cwd"]?.stringValue else {
                throw RPCError.invalidParams("session_id and cwd required")
            }
            // Validate cwd is within devRoot to prevent path traversal
            guard Validation.isPathWithinRoot(cwd, root: devRoot) else {
                throw RPCError.invalidParams("Terminal cwd must be within the configured devRoot")
            }
            // Resolve claude binary path if command references claude
            var command = params["command"]?.stringValue
            if let cmd = command, cmd.contains("claude") {
                command = AppDelegate.resolveClaudeInCommand(cmd)
            }
            let isManaged = params["managed"]?.boolValue ?? false
            let defaultName = isManaged ? "Claude Code" : "Shell"
            let terminal = SessionTerminal(sessionID: sessionID, name: params["name"]?.stringValue ?? defaultName,
                                           cwd: cwd, command: command, isManaged: isManaged)
            return await MainActor.run {
                appState.terminals[sessionID, default: []].append(terminal)
                store.mutate { $0.terminals.append(terminal) }
                // Track readiness only for managed work session terminals
                if isManaged && sessionID != AppState.managerSessionID {
                    appState.terminalReadiness[terminal.id] = .uninitialized
                    TerminalManager.shared.trackReadiness(for: terminal.id)
                }
                // Pre-initialize in offscreen window so shell starts immediately
                TerminalManager.shared.preInitialize(id: terminal.id, workingDirectory: cwd, command: command)
                return ["terminal_id": .string(terminal.id.uuidString), "session_id": .string(idStr)]
            }
        },
        "list-terminals": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                throw RPCError.invalidParams("session_id required")
            }
            // Global terminals are not exposed via the session CLI
            if id == AppState.globalTerminalSessionID {
                return ["terminals": .array([])]
            }
            let terms = await MainActor.run { appState.terminals(for: id) }
            let items: [JSONValue] = terms.map { t in
                .object(["id": .string(t.id.uuidString), "name": .string(t.name), "session_id": .string(t.sessionID.uuidString), "managed": .bool(t.isManaged)])
            }
            return ["terminals": .array(items)]
        },
        "close-terminal": { @Sendable params in
            guard let sessionIDStr = params["session_id"]?.stringValue,
                  let sessionID = UUID(uuidString: sessionIDStr),
                  let terminalIDStr = params["terminal_id"]?.stringValue,
                  let terminalID = UUID(uuidString: terminalIDStr) else {
                throw RPCError.invalidParams("session_id and terminal_id required")
            }
            return try await MainActor.run {
                guard let terminals = appState.terminals[sessionID],
                      let terminal = terminals.first(where: { $0.id == terminalID }) else {
                    throw RPCError.applicationError("Terminal not found")
                }
                guard !terminal.isManaged else {
                    throw RPCError.applicationError("Cannot close managed terminal")
                }
                TerminalManager.shared.destroy(id: terminalID)
                appState.terminals[sessionID]?.removeAll { $0.id == terminalID }
                appState.terminalReadiness.removeValue(forKey: terminalID)
                appState.autoLaunchTerminals.remove(terminalID)
                if appState.activeTerminalID[sessionID] == terminalID {
                    appState.activeTerminalID[sessionID] = appState.terminals[sessionID]?.first?.id
                }
                store.mutate { data in data.terminals.removeAll { $0.id == terminalID } }
                return ["deleted": .bool(true)]
            }
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
            NSLog("crow send: text length=\(text.count), ends_with_newline=\(text.hasSuffix("\n")), ends_with_cr=\(text.hasSuffix("\r"))")
            await MainActor.run {
                // If the surface doesn't exist yet, pre-initialize it so the shell starts
                if TerminalManager.shared.existingSurface(for: terminalID) == nil {
                    if let terminals = appState.terminals[sessionID],
                       let terminal = terminals.first(where: { $0.id == terminalID }) {
                        TerminalManager.shared.preInitialize(
                            id: terminalID,
                            workingDirectory: terminal.cwd,
                            command: terminal.command
                        )
                    }
                }

                // For managed terminals receiving a claude command, write hook config
                // before sending so Claude picks up the hooks on startup.
                if let terminals = appState.terminals[sessionID],
                   let terminal = terminals.first(where: { $0.id == terminalID }),
                   terminal.isManaged,
                   text.contains("claude") {
                    if let worktree = appState.primaryWorktree(for: sessionID),
                       let crowPath = HookConfigGenerator.findCrowBinary() {
                        do {
                            try HookConfigGenerator.writeHookConfig(
                                worktreePath: worktree.worktreePath,
                                sessionID: sessionID,
                                crowPath: crowPath
                            )
                        } catch {
                            NSLog("[AppDelegate] Failed to write hook config for session %@: %@",
                                  sessionID.uuidString, error.localizedDescription)
                        }
                    }
                    appState.terminalReadiness[terminalID] = .claudeLaunched
                }

                TerminalManager.shared.send(id: terminalID, text: text)
            }
            return ["sent": .bool(true)]
        },
    ]
}
