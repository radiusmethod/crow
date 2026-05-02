# Architecture

Crow is a native macOS app that coordinates AI-assisted development sessions. Each session is a git worktree + a Claude Code terminal + ticket metadata, all tracked in a persistent store and surfaced in a SwiftUI sidebar. A CLI (`crow`) talks to the running app over a Unix socket so that Claude Code can create sessions programmatically.

## Repository Layout

```
crow/
├── Sources/
│   ├── Crow/                  # Main application target
│   │   ├── App/
│   │   │   ├── main.swift           # Entry point
│   │   │   ├── AppDelegate.swift    # Window, IPC server, startup
│   │   │   ├── SessionService.swift # Session CRUD, orphan detection
│   │   │   ├── IssueTracker.swift   # GitHub/GitLab polling (60s)
│   │   │   └── Scaffolder.swift     # First-run dev-root scaffold
│   │   └── Resources/
│   └── CrowCLI/               # crow CLI binary target
│       └── main.swift               # Thin executable that calls CrowCommand.main()
├── Packages/                  # SwiftPM library packages
│   ├── CrowCore/                    # Data models, AppState (observable)
│   ├── CrowCLI/                     # CLI command definitions (CrowCommand + subcommands)
│   ├── CrowClaude/                  # Claude binary resolution
│   ├── CrowGit/                     # Git operations
│   ├── CrowIPC/                     # Unix socket RPC protocol
│   ├── CrowPersistence/             # JSON store, config persistence
│   ├── CrowProvider/                # GitHub/GitLab provider abstraction
│   ├── CrowTerminal/                # Ghostty terminal surface management
│   └── CrowUI/                      # SwiftUI views, Corveil theme
├── Frameworks/                # Built GhosttyKit (gitignored)
├── vendor/ghostty/            # Ghostty submodule
├── scripts/                   # Build helpers (build-ghostty.sh, bundle.sh, …)
└── skills/                    # Bundled Claude Code skills (crow-workspace, etc.)
```

### About `Sources/CrowCLI` vs `Packages/CrowCLI`

There are two `CrowCLI` directories:

- **`Packages/CrowCLI/`** is a library package (`CrowCLILib`) that defines every subcommand as a `ParsableCommand` struct plus the `CrowCommand` root. This is where you add new commands or edit existing ones.
- **`Sources/CrowCLI/main.swift`** is a thin executable target that imports `CrowCLILib` and calls `CrowCommand.main()`. Keeping the command logic in a package lets tests in `Packages/CrowCLI/Tests/` exercise commands directly without building the executable.

## Key Components

| Component                 | Lives in                                           | Description                                                                                                       |
| ------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **AppDelegate**           | `Sources/Crow/App/AppDelegate.swift`               | Initializes the app, creates the main window, starts the IPC socket server and issue tracker                     |
| **SessionService**        | `Sources/Crow/App/SessionService.swift`            | CRUD for sessions/worktrees/terminals, terminal readiness tracking, orphan recovery on startup                    |
| **IssueTracker**          | `Sources/Crow/App/IssueTracker.swift`              | Polls GitHub/GitLab every 60 seconds for assigned issues, PR status, project board status, auto-completes merged sessions |
| **Scaffolder**            | `Sources/Crow/App/Scaffolder.swift`                | First-run devRoot scaffold: `.claude/` + bundled skills + settings.json                                           |
| **TerminalManager**       | `Packages/CrowTerminal/.../TerminalManager.swift`  | Manages Ghostty `ghostty_surface_t` lifecycle; emits state transitions consumed by `TerminalReadiness`            |
| **TmuxBackend**           | `Packages/CrowTerminal/.../TmuxBackend.swift`      | Headless-PTY backend introduced in #229; opt-in via `CROW_TMUX_BACKEND` or Settings → Experimental                |
| **TerminalRouter**        | `Sources/Crow/App/TerminalRouter.swift`            | Per-terminal dispatch — routes `send` / `destroy` / `trackReadiness` to either Ghostty or tmux based on `SessionTerminal.backend` |
| **AutoRespondCoordinator**| `Sources/Crow/App/AutoRespondCoordinator.swift`    | Watches PR review / CI signals and types follow-up instructions into the linked Claude Code terminal (#214)       |
| **TerminalReadiness**     | `Packages/CrowCore/Sources/CrowCore/Models/Enums.swift:41` | Four-state enum (uninitialized → surfaceCreated → shellReady → claudeLaunched) driving the sidebar status dot |
| **SocketServer**          | `Packages/CrowIPC/`                                | Unix socket server at `~/.local/share/crow/crow.sock` — receives JSON-RPC commands from the `crow` CLI            |
| **CrowCommand**           | `Packages/CrowCLI/.../CrowCommand.swift`           | ArgumentParser root command registering every subcommand                                                          |
| **JSONStore**             | `Packages/CrowPersistence/`                        | NSLock-serialized JSON persistence for sessions, worktrees, links, terminals                                      |

## Data Flow

### Opening a session tab

```
User clicks session tab
  → SwiftUI renders TerminalSurfaceView
  → GhosttySurfaceView.createSurface() spawns shell
  → TerminalManager transitions created → shellReady
  → TerminalReadiness: uninitialized → surfaceCreated → shellReady → claudeLaunched
  → Auto-sends `claude --continue` when shell becomes ready
  → Sidebar status dot turns green
```

### Creating a session from Manager

```
User invokes /crow-workspace in Manager tab
  → Claude Code runs crow CLI commands through the Unix socket
  → crow new-session → crow add-worktree → crow new-terminal --managed
  → App creates session, registers worktree, spawns managed terminal
  → User clicks the new session tab → Claude launches automatically
```

### Issue tracker polling

```
Every 60 seconds:
  → IssueTracker.fetchAssignedIssues (gh search issues --assignee @me)
  → IssueTracker.fetchPRStatus for linked PRs
  → IssueTracker.fetchGitHubProjectStatuses (GraphQL, needs read:project)
  → Auto-complete sessions whose PR is merged or issue is closed
```

### Moving a ticket to "In Progress" / "In Review"

```
User starts a session via /crow-workspace (or clicks "Mark In Review")
  → IssueTracker.markInReview builds a GraphQL query for the Status field
  → Calls updateProjectV2ItemFieldValue mutation
  → Requires the write `project` scope — NOT `read:project`
  → On INSUFFICIENT_SCOPES, logs a hint to run `gh auth refresh -s project`
```

See `Sources/Crow/App/IssueTracker.swift:636-774` for the full `markInReview` implementation.

## Why Ghostty?

Crow embeds [Ghostty](https://ghostty.org) as a terminal emulator via a compiled `libghostty` XCFramework. Ghostty gives each session tab a real GPU-accelerated terminal surface with the same behavior as the standalone Ghostty app, and its C API exposes the `ghostty_surface_t` lifecycle so Crow can track when the shell is ready and auto-launch `claude --continue`. The framework is built from the vendored submodule by `scripts/build-ghostty.sh` (invoked by `make ghostty`).

## Terminal Backends

PR #229 introduced a second backend behind the `CROW_TMUX_BACKEND` feature flag. Crow now supports two terminal runtimes side-by-side:

- **Ghostty (default)** — per-tab `ghostty_surface_t` driven by `TerminalManager`. Each session terminal owns a real `NSView` with GPU-accelerated rendering. This is the original path and remains the default for everyone who has not opted in.
- **tmux (opt-in)** — headless PTY plus a tmux server, driven by `TmuxBackend`. Each session terminal corresponds to a tmux window; rendering is decoupled from the surface so terminals can spin up before any view is materialized. Opt in via either:
  - Environment variable `CROW_TMUX_BACKEND=1` (or `true`/`yes`/`on`).
  - **Settings → Experimental → Use tmux for managed terminals** (persists in `AppConfig.experimentalTmuxBackend`).
  - The two sources are OR-merged. Toggle is decided once at app launch by `FeatureFlags.tmuxBackend` and frozen for the process lifetime — flipping the toggle in Settings requires a relaunch.

Per-terminal dispatch happens in `Sources/Crow/App/TerminalRouter.swift`. Each `SessionTerminal` carries a `backend: .ghostty | .tmux` discriminator captured at create time, and `TerminalRouter.send` / `destroy` / `trackReadiness` switch on it. This keeps the rest of the app backend-agnostic.

The tmux backend requires `tmux ≥ 3.3` on `PATH` (typical Homebrew install). If the flag is on but tmux is missing or too old, Crow surfaces an alert at launch with a `brew install tmux` hint and silently falls back to Ghostty for the session.

The original motivation and full alternative analysis are in [terminal-runtime-research.md](terminal-runtime-research.md).

## Settings

PR #228 split Settings into discrete tabs. Each tab maps to a SwiftUI view in `Packages/CrowUI/Sources/CrowUI/`:

- **General** — devRoot, sidebar density, notifications, sounds.
- **Workspaces** — per-workspace provider, host, branch prefix, and per-workspace auto-review opt-in (#209).
- **Automation** — every automation toggle in one place. See [automation.md](automation.md) for a per-toggle walkthrough. Source: `AutomationSettingsView.swift`.
- **Experimental** — feature flags including the tmux backend toggle.

Tab state is persisted in `{devRoot}/.claude/config.json` via `CrowPersistence`.

## Review Board

The review board is the surface for triaging PRs that have been queued for AI review. Recent PRs added these capabilities:

- **Exclude list** (#207) — repos in `defaults.excludeReviewRepos` are filtered from the board, badge counts, and notifications. Wildcards supported.
- **Auto-start** (#209) — per-workspace toggle that auto-creates a review session when a PR becomes reviewable.
- **PR link reconciliation** (#205) — sessions whose hook events missed a PR open are reconciled against `gh pr list` on the next polling cycle so the session detail surface still shows the correct PR.
- **Bulk delete** (#210) — sidebar selection mode that lets you remove multiple sessions at once.
- **Multi-select + batch Start Review** (#212) — review-board selection mode for kicking off several reviews in one click.
- **Filtering** (#220) — inline filter on the tickets list, mirrored across the review board.
- **Per-section select all + icon-only cancel** (#226) — UX polish on selection mode.
- **Quick action buttons on session detail header** (#231) — surface the most-used session actions (open PR, mark in review, copy branch) directly on the detail view.
- **Move to Active** (#188) — return a completed session to active without deleting it.
