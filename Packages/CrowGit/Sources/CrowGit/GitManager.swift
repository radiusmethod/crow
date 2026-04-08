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
    ///
    /// If the branch already exists on the remote, the worktree tracks it.
    /// Otherwise, a new branch is created from the repo's default branch with `--no-track`
    /// to prevent accidental pushes to the default branch.
    ///
    /// If creation fails because a local branch with the same name already exists,
    /// the conflicting branch is deleted and the operation is retried once.
    public func createWorktree(repoPath: String, worktreePath: String, branch: String) async throws {
        // Check if branch exists on remote
        let lsRemote = try await run(["git", "-C", repoPath, "ls-remote", "--heads", "origin", branch])
        let branchExistsOnRemote = !lsRemote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        _ = try await run(["git", "-C", repoPath, "fetch", "origin"])

        if branchExistsOnRemote {
            try await createWorktreeWithRetry(repoPath: repoPath, worktreePath: worktreePath, args: [
                "git", "-C", repoPath, "worktree", "add", worktreePath,
                "-b", branch, "--track", "origin/\(branch)",
            ], branch: branch)
        } else {
            let defaultBranch = try await resolveDefaultBranch(repoPath: repoPath)
            try await createWorktreeWithRetry(repoPath: repoPath, worktreePath: worktreePath, args: [
                "git", "-C", repoPath, "worktree", "add", worktreePath,
                "-b", branch, "--no-track", "origin/\(defaultBranch)",
            ], branch: branch)
        }
    }

    /// Remove a worktree.
    public func removeWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await run(["git", "-C", repoPath, "worktree", "remove", worktreePath])
    }

    // MARK: - Private Helpers

    /// Resolve the default branch for the remote (e.g. main, master).
    private func resolveDefaultBranch(repoPath: String) async throws -> String {
        let ref = try await run(["git", "-C", repoPath, "symbolic-ref", "refs/remotes/origin/HEAD"])
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        // refs/remotes/origin/main → main
        if let lastSlash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: lastSlash)...])
        }
        throw GitError.noDefaultBranch(remote: "origin")
    }

    /// Attempt to create a worktree; retry once if the branch already exists locally.
    private func createWorktreeWithRetry(
        repoPath: String, worktreePath: String, args: [String], branch: String
    ) async throws {
        do {
            _ = try await run(args)
        } catch let error as GitError {
            guard case .commandFailed(_, _, let stderr) = error,
                  stderr.contains("already exists") else {
                throw error
            }
            // Delete the conflicting local branch and retry once
            _ = try await run(["git", "-C", repoPath, "branch", "-D", branch])
            _ = try await run(args)
        }
    }

    /// Run a git command, returning stdout on success.
    private func run(_ args: [String]) async throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.environment = ShellEnvironment.shared.env
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(
                command: args.joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }
        return stdout
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

public enum GitError: Error, LocalizedError {
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case branchAlreadyExists(String)
    case noDefaultBranch(remote: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let stderr):
            return "Git command failed (\(exitCode)): \(command)\n\(stderr)"
        case .branchAlreadyExists(let branch):
            return "Branch '\(branch)' already exists"
        case .noDefaultBranch(let remote):
            return "Could not determine default branch for remote '\(remote)'"
        }
    }
}
