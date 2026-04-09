import CrowCore
import CrowIPC
import CrowPersistence
import Foundation

func linkHandlers(
    appState: AppState,
    store: JSONStore
) -> [String: CommandRouter.Handler] {
    [
        "add-link": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let sessionID = UUID(uuidString: idStr),
                  let label = params["label"]?.stringValue, !label.isEmpty,
                  let url = params["url"]?.stringValue, !url.isEmpty else {
                throw RPCError.invalidParams("session_id, label, url required (non-empty)")
            }
            let link = SessionLink(sessionID: sessionID, label: label, url: url,
                                   linkType: LinkType(rawValue: params["type"]?.stringValue ?? "custom") ?? .custom)
            return await MainActor.run {
                appState.links[sessionID, default: []].append(link)
                store.mutate { $0.links.append(link) }
                return ["link_id": .string(link.id.uuidString)]
            }
        },
        "list-links": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                throw RPCError.invalidParams("session_id required")
            }
            let lnks = await MainActor.run { appState.links(for: id) }
            let items: [JSONValue] = lnks.map { l in
                .object(["id": .string(l.id.uuidString), "label": .string(l.label), "url": .string(l.url), "type": .string(l.linkType.rawValue)])
            }
            return ["links": .array(items)]
        },
    ]
}
