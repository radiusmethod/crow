import CrowCore
import CrowIPC
import CrowPersistence
import Foundation

func worktreeHandlers(
    appState: AppState,
    store: JSONStore,
    devRoot: String
) -> [String: CommandRouter.Handler] {
    [
        "add-worktree": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let sessionID = UUID(uuidString: idStr),
                  let repo = params["repo"]?.stringValue, !repo.isEmpty,
                  let path = params["path"]?.stringValue, !path.isEmpty,
                  let branch = params["branch"]?.stringValue, !branch.isEmpty else {
                throw RPCError.invalidParams("session_id, repo, path, branch required (non-empty)")
            }
            // Validate path is within devRoot to prevent path traversal
            guard Validation.isPathWithinRoot(path, root: devRoot) else {
                throw RPCError.invalidParams("Worktree path must be within the configured devRoot")
            }
            // repo_path is the main repo (for git commands). Defaults to path if not provided.
            let repoPath = params["repo_path"]?.stringValue ?? path
            guard Validation.isPathWithinRoot(repoPath, root: devRoot) else {
                throw RPCError.invalidParams("repo_path must be within the configured devRoot")
            }
            let wt = SessionWorktree(sessionID: sessionID, repoName: repo, repoPath: repoPath, worktreePath: path,
                                     branch: branch, isPrimary: params["primary"]?.boolValue ?? false)
            return await MainActor.run {
                appState.worktrees[sessionID, default: []].append(wt)
                store.mutate { $0.worktrees.append(wt) }
                return ["worktree_id": .string(wt.id.uuidString), "session_id": .string(idStr), "path": .string(path)]
            }
        },
        "list-worktrees": { @Sendable params in
            guard let idStr = params["session_id"]?.stringValue, let id = UUID(uuidString: idStr) else {
                throw RPCError.invalidParams("session_id required")
            }
            let wts = await MainActor.run { appState.worktrees(for: id) }
            let items: [JSONValue] = wts.map { wt in
                .object(["id": .string(wt.id.uuidString), "repo": .string(wt.repoName), "path": .string(wt.worktreePath),
                         "branch": .string(wt.branch), "primary": .bool(wt.isPrimary)])
            }
            return ["worktrees": .array(items)]
        },
    ]
}
