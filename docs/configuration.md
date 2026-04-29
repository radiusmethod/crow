# Configuration

This page covers where Crow stores data, how workspaces are configured, the on-disk directory layout it expects, and runtime behavior you can tune via environment variables.

## File Locations

All persistent state lives under `~/Library/Application Support/crow/` (see `Packages/CrowPersistence/Sources/CrowPersistence/AppSupportDirectory.swift`). On first run, if a legacy `rm-ai-ide` directory exists in the same parent, its contents are copied over automatically.

| Path                                                                  | Purpose                                                       |
| --------------------------------------------------------------------- | ------------------------------------------------------------- |
| `~/Library/Application Support/crow/devroot`                          | Pointer file containing the development root path            |
| `~/Library/Application Support/crow/store.json`                       | Persisted sessions, worktrees, links, terminals               |
| `~/.local/share/crow/crow.sock`                                       | Unix socket for CLI ↔ app IPC                                 |
| `{devRoot}/.claude/config.json`                                       | Workspace configuration (see below)                          |
| `{devRoot}/.claude/CLAUDE.md`                                         | Manager-tab context with the `crow` CLI reference             |
| `{devRoot}/.claude/settings.json`                                     | Pre-approved permissions for Claude Code sessions             |
| `{devRoot}/.claude/prompts/`                                          | Prompt files used by the `/crow-workspace` skill              |
| `{devRoot}/.claude/skills/crow-workspace/SKILL.md`                    | Workspace setup skill invoked via `/crow-workspace`           |
| `{devRoot}/.claude/skills/crow-workspace/setup.sh`                    | Deterministic setup script called by the skill                |
| `{devRoot}/.claude/skills/crow-review-pr/SKILL.md`                    | PR review skill invoked via `/crow-review-pr`                 |
| `{devRoot}/.claude/skills/crow-batch-workspace/SKILL.md`              | Batch workspace setup skill                                   |
| `{devRoot}/crow-reviews/`                                             | Temporary clones used when reviewing PRs                      |

## Workspace Configuration

`{devRoot}/.claude/config.json` describes the workspaces Crow manages and the defaults used when scaffolding new worktrees:

```json
{
  "workspaces": [
    {
      "id": "uuid",
      "name": "RadiusMethod",
      "provider": "github",
      "cli": "gh",
      "host": null
    },
    {
      "id": "uuid",
      "name": "MyGitLab",
      "provider": "gitlab",
      "cli": "glab",
      "host": "gitlab.example.com"
    }
  ],
  "defaults": {
    "provider": "github",
    "cli": "gh",
    "branchPrefix": "feature/",
    "excludeDirs": ["node_modules", ".git", "vendor", "dist", "build", "target"],
    "excludeReviewRepos": ["zarf-dev/zarf", "bmlt-enabled/yap"],
    "excludeTicketRepos": []
  }
}
```

- **`provider`** — `github` or `gitlab`. Determines which CLI and which issue-tracker code path runs.
- **`cli`** — `gh` or `glab`. The binary that Crow shells out to.
- **`host`** — set for self-hosted GitLab; exported as `GITLAB_HOST` when invoking `glab`.
- **`branchPrefix`** — used by the `/crow-workspace` skill when creating new branches.
- **`excludeDirs`** — ignored when scanning repos for git worktrees.
- **`excludeReviewRepos`** — repos to hide from the review board (e.g., `["zarf-dev/zarf"]`). Matching reviews are filtered out from the board, sidebar badge count, and notifications.
- **`excludeTicketRepos`** — repos to hide from the ticket board (e.g., `["zarf-dev/zarf"]`). Matching issues are filtered out from the board, pipeline counts, and auto-create candidates.

## Manager Terminal

The Manager tab runs Claude Code at the dev root and drives workspace orchestration. Its behavior is controlled by these top-level keys in `{devRoot}/.claude/config.json`:

- **`managerAutoPermissionMode`** (default: `true`) — passes `--permission-mode auto` to the Manager's `claude` launch so it can run `crow`, `gh`, and `git` commands without per-call approval. Requires Claude Code **v2.1.83+**, a **Max / Team / Enterprise / API** plan, the **Anthropic** API provider (not Bedrock / Vertex / Foundry), and a supported model (**Sonnet 4.6**, **Opus 4.6**, or **Opus 4.7**). On Team/Enterprise plans an admin must enable auto mode in Claude Code admin settings. Turn this off via **Settings → General → Manager Terminal** if your account reports auto mode as unavailable. Worker sessions and CLI-spawned terminals are unaffected by this setting.
- **`remoteControlEnabled`** (default: `false`) — launches new Claude Code sessions with `--rc` so you can control them from claude.ai or the Claude mobile app.

Changes take effect on next app launch — the Manager's stored command is rebuilt on hydration.

## Directory Structure

Crow expects repositories organized under workspace folders:

```
~/Dev/                             # Development root
├── RadiusMethod/                  # Workspace (GitHub)
│   ├── acme-api/                   # Main repo checkout
│   ├── acme-api-134-sensor/        # Worktree for issue #134
│   └── acme-api-209-review/        # Worktree for issue #209
└── MyGitLab/                      # Workspace (GitLab)
    ├── my-project/
    └── overrides/
```

Worktrees are created **at the same level as the main repo**, not in a `worktrees/` subdirectory. The path convention is `{devRoot}/{workspace}/{repo}-{ticketNumber}-{slug}`.

## Environment Variables

| Variable      | Purpose                                                          | Default                        |
| ------------- | ---------------------------------------------------------------- | ------------------------------ |
| `CROW_SOCKET` | Override the Unix socket path for CLI ↔ app IPC                  | `~/.local/share/crow/crow.sock` |
| `TMPDIR`      | Temporary file directory (used by the terminal subsystem)       | System default                 |
| `GITLAB_HOST` | GitLab instance hostname (set automatically per workspace)      | —                              |

## Session Lifecycle

| State       | Trigger                                                                    | Sidebar indicator                                             |
| ----------- | -------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `active`    | Created via `/crow-workspace` or `crow new-session`                        | Green dot (or gray / yellow / blue during terminal init)      |
| `inReview`  | PR opened or manually marked in review                                     | Gold eye icon                                                 |
| `completed` | PR merged or issue closed (auto-detected), or manual "Mark as Completed"   | Gold checkmark                                                |
| `archived`  | Manual                                                                     | Gray archive icon                                             |
| `paused`    | Manual                                                                     | Yellow indicator                                              |

## Terminal Readiness

`TerminalReadiness` (`Packages/CrowCore/Sources/CrowCore/Models/Enums.swift:41`) tracks how far each managed terminal has progressed through startup. The sidebar dot in `Packages/CrowUI/Sources/CrowUI/SessionListView.swift:325-372` reflects the current state:

1. **Gray dot (`uninitialized`)** — `GhosttySurfaceView` exists but `createSurface()` has not been called yet.
2. **Yellow dot (`surfaceCreated`)** — `ghostty_surface_t` exists, the shell process is spawning.
3. **Blue dot (`shellReady`)** — Shell prompt detected (probe file appeared).
4. **Green dot (`claudeLaunched`)** — `claude --continue` has been sent. The dot shows:
   - Solid green when Claude is idle
   - Pulsing green when Claude is working
   - Pulsing orange when Claude is awaiting input

A loading overlay shows "Waiting for terminal..." or "Shell starting..." until `shellReady` is reached.

## Safe Deletion

Deleting a session whose worktree is on a protected branch (`main`, `master`, `develop`) only removes the session metadata — the repo folder and branch are preserved. The delete confirmation dialog reflects this by showing "Remove Session" instead of "Delete Everything".
