import CrowCore
import CrowIPC
import CrowPersistence
import Foundation

func sessionHandlers(
    appState: AppState,
    store: JSONStore,
    service: SessionService
) -> [String: CommandRouter.Handler] {
    [
        "new-session": { @Sendable params in
            let name = params["name"]?.stringValue ?? "untitled"
            guard Validation.isValidSessionName(name) else {
                throw RPCError.invalidParams("Invalid session name (max \(Validation.maxSessionNameLength) chars, no control characters)")
            }
            return await MainActor.run {
                let session = Session(name: name)
                appState.sessions.append(session)
                store.mutate { $0.sessions.append(session) }
                return ["session_id": .string(session.id.uuidString), "name": .string(session.name)]
            }
        },
        "rename-session": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue,
                  let id = UUID(uuidString: idStr),
                  let name = params["name"]?.stringValue else {
                throw RPCError.invalidParams("session_id and name required")
            }
            guard Validation.isValidSessionName(name) else {
                throw RPCError.invalidParams("Invalid session name (max \(Validation.maxSessionNameLength) chars, no control characters)")
            }
            return try await MainActor.run {
                guard let idx = appState.sessions.firstIndex(where: { $0.id == id }) else {
                    throw RPCError.applicationError("Session not found")
                }
                appState.sessions[idx].name = name
                store.mutate { data in
                    if let i = data.sessions.firstIndex(where: { $0.id == id }) { data.sessions[i].name = name }
                }
                return ["session_id": .string(idStr), "name": .string(name)]
            }
        },
        "select-session": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue,
                  let id = UUID(uuidString: idStr) else {
                throw RPCError.invalidParams("session_id required")
            }
            await MainActor.run { appState.selectedSessionID = id }
            return ["session_id": .string(idStr)]
        },
        "list-sessions": { @Sendable _ in
            let sessions = await MainActor.run { appState.sessions }
            let items: [JSONValue] = sessions.map { s in
                .object(["id": .string(s.id.uuidString), "name": .string(s.name), "status": .string(s.status.rawValue)])
            }
            return ["sessions": .array(items)]
        },
        "get-session": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                throw RPCError.invalidParams("session_id required")
            }
            return try await MainActor.run {
                guard let s = appState.sessions.first(where: { $0.id == id }) else {
                    throw RPCError.applicationError("Session not found")
                }
                let fmt = ISO8601DateFormatter()
                return [
                    "id": .string(s.id.uuidString),
                    "name": .string(s.name),
                    "status": .string(s.status.rawValue),
                    "ticket_url": s.ticketURL.map { .string($0) } ?? .null,
                    "ticket_title": s.ticketTitle.map { .string($0) } ?? .null,
                    "ticket_number": s.ticketNumber.map { .int($0) } ?? .null,
                    "provider": s.provider.map { .string($0.rawValue) } ?? .null,
                    "created_at": .string(fmt.string(from: s.createdAt)),
                    "updated_at": .string(fmt.string(from: s.updatedAt)),
                ]
            }
        },
        "set-status": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr),
                  let statusStr = params["status"]?.stringValue, let status = SessionStatus(rawValue: statusStr) else {
                throw RPCError.invalidParams("session_id and status required")
            }
            return try await MainActor.run {
                guard let idx = appState.sessions.firstIndex(where: { $0.id == id }) else {
                    throw RPCError.applicationError("Session not found")
                }
                appState.sessions[idx].status = status
                appState.sessions[idx].updatedAt = Date()
                store.mutate { data in
                    if let i = data.sessions.firstIndex(where: { $0.id == id }) {
                        data.sessions[i].status = status
                        data.sessions[i].updatedAt = Date()
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
            await service.deleteSession(id: id)
            return ["deleted": .bool(true)]
        },
        "set-ticket": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                throw RPCError.invalidParams("session_id required")
            }
            return try await MainActor.run {
                guard let idx = appState.sessions.firstIndex(where: { $0.id == id }) else {
                    throw RPCError.applicationError("Session not found")
                }
                if let url = params["url"]?.stringValue {
                    appState.sessions[idx].ticketURL = url
                    // Auto-detect provider from URL
                    if appState.sessions[idx].provider == nil {
                        appState.sessions[idx].provider = Validation.detectProviderFromURL(url)
                    }
                }
                if let title = params["title"]?.stringValue { appState.sessions[idx].ticketTitle = title }
                if let num = params["number"]?.intValue { appState.sessions[idx].ticketNumber = num }
                store.mutate { data in
                    if let i = data.sessions.firstIndex(where: { $0.id == id }) { data.sessions[i] = appState.sessions[idx] }
                }
                return ["session_id": .string(idStr)]
            }
        },
    ]
}
