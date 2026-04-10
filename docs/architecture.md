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
