import Foundation
import CrowCore

/// Discovers git repos across workspaces and manages worktrees.
public actor GitManager {
    private let config: WorkspaceConfig

    public init(config: WorkspaceConfig) {
        self.config = config
    }

    /// Discover all git repositories under devRoot.
    public func discoverRepos() async throws -> [RepoInfo] {
        let devRoot = config.devRoot
        let fm = FileManager.default
        guard let workspaceDirs = try? fm.contentsOfDirectory(atPath: devRoot) else {
            return []
        }

        var repos: [RepoInfo] = []
        for wsDir in workspaceDirs {
            let wsPath = (devRoot as NSString).appendingPathComponent(wsDir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: wsPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard !config.defaults.excludeDirs.contains(wsDir) else { continue }

            let wsConfig = config.workspaces[wsDir]
            let provider = wsConfig?.provider ?? config.defaults.provider
            let cli = wsConfig?.cli ?? config.defaults.cli
            let host = wsConfig?.host

            guard let repoDirs = try? fm.contentsOfDirectory(atPath: wsPath) else { continue }
            for repoDir in repoDirs {
                let repoPath = (wsPath as NSString).appendingPathComponent(repoDir)
                let gitPath = (repoPath as NSString).appendingPathComponent(".git")
                var gitIsDir: ObjCBool = false

                // Only include actual repos (not worktrees — .git is a directory, not a file)
                guard fm.fileExists(atPath: gitPath, isDirectory: &gitIsDir), gitIsDir.boolValue else { continue }

                repos.append(RepoInfo(
                    name: repoDir,
                    path: repoPath,
                    workspace: wsDir,
                    provider: provider,
                    cli: cli,
                    host: host
                ))
            }
        }
        return repos
    }

    /// Create a worktree for a repo.
    public func createWorktree(repoPath: String, worktreePath: String, branch: String) async throws {
        // Check if branch exists on remote
        let lsRemote = try await shell("git", "-C", repoPath, "ls-remote", "--heads", "origin", branch)
        let branchExistsOnRemote = !lsRemote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        _ = try await shell("git", "-C", repoPath, "fetch", "origin")

        if branchExistsOnRemote {
            _ = try await shell("git", "-C", repoPath, "worktree", "add", worktreePath,
                                "-b", branch, "--track", "origin/\(branch)")
        } else {
            _ = try await shell("git", "-C", repoPath, "worktree", "add", worktreePath,
                                "-b", branch, "origin/main")
        }
    }

    /// Remove a worktree.
    public func removeWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await shell("git", "-C", repoPath, "worktree", "remove", worktreePath)
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
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(String(data: data, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct RepoInfo: Sendable {
    public let name: String
    public let path: String
    public let workspace: String
    public let provider: String
    public let cli: String
    public let host: String?
}

public enum GitError: Error {
    case commandFailed(String)
}
