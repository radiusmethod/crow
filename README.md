# Corveil AI IDE

A native macOS application for managing AI-powered development sessions. Orchestrates git worktrees, Claude Code instances, and GitHub/GitLab issue tracking in a unified interface with an embedded Ghostty terminal.

## Prerequisites

### System Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon** (arm64)
- **Xcode** with Command Line Tools installed

### Build Dependencies

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| Swift | 6.0+ | Compiler (ships with Xcode) | `xcode-select --install` |
| Zig | 0.15.2 | Builds the Ghostty terminal framework | `brew install zig` or [ziglang.org](https://ziglang.org/download/) |
| mise | latest | Task runner (optional) | `brew install mise` |

### Runtime Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| `gh` | GitHub CLI — issue tracking, PR status, project boards | `brew install gh` |
| `git` | Worktree management | Ships with Xcode CLT |
| `claude` | Claude Code — AI coding assistant | [claude.ai/download](https://claude.ai/download) |
| `glab` | GitLab CLI (optional, for GitLab repos) | `brew install glab` |

## Quick Start

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/radiusmethod/rm-ai-ide.git
cd rm-ai-ide

# 2. Build the Ghostty terminal framework
./scripts/build-ghostty.sh

# 3. Build the app
swift build

# 4. Authenticate GitHub CLI
gh auth login
gh auth refresh -s read:project   # Required for project board status

# 5. Run
.build/debug/RmAiIde
```

On first launch, a setup wizard guides you through choosing your development root directory and configuring workspaces.

## Detailed Setup

### 1. Clone the Repository

```bash
git clone --recurse-submodules https://github.com/radiusmethod/rm-ai-ide.git
cd rm-ai-ide
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init vendor/ghostty
```

### 2. Build the Ghostty Framework

The app embeds [Ghostty](https://ghostty.org) as a terminal emulator via libghostty. This must be built before the app:

```bash
./scripts/build-ghostty.sh
```

This compiles libghostty from the vendored source using Zig, producing:
- `Frameworks/GhosttyKit.xcframework/` — the compiled framework
- `Frameworks/ghostty-resources/` — terminal resources (themes, etc.)

**Troubleshooting:**
- Verify Zig version: `zig version` should show `0.15.2`
- Verify Metal toolchain: `xcrun -sdk macosx metal --version`

### 3. Build the App

```bash
# Debug build
swift build

# Release build
swift build -c release

# Create .app bundle (release)
./scripts/bundle.sh
```

The build produces two executables:
- `RmAiIde` — the main application
- `ride` — the CLI for session management

### 4. GitHub Authentication

The app uses the GitHub CLI to fetch issues, PRs, and project board status.

```bash
# Initial login
gh auth login

# Add project board scope (required for ticket pipeline status)
gh auth refresh -s read:project
```

**Required scopes:** `repo`, `read:org`, `read:project`

Verify with: `gh auth status`

### 5. GitLab Authentication (Optional)

For self-hosted GitLab instances:

```bash
glab auth login --hostname gitlab.example.com
```

### 6. First Launch

```bash
.build/debug/RmAiIde
```

The setup wizard will:
1. Ask for your **development root** directory (e.g., `~/Dev`)
2. Let you **configure workspaces** — each workspace is a subfolder containing git repos
3. Set the **provider** per workspace (GitHub or GitLab)
4. Scaffold the directory structure and configuration files

### Using mise (Optional)

If you have `mise` installed, you can use the predefined tasks:

```bash
mise build           # Build debug
mise build:release   # Build release
mise build:ghostty   # Build GhosttyKit framework
mise bundle          # Create .app bundle
mise clean           # Clean build artifacts
```

## Architecture

### Package Structure

```
rm-ai-ide/
├── Sources/
│   ├── RmAiIde/          # Main app target
│   │   ├── App/
│   │   │   ├── main.swift           # Entry point
│   │   │   ├── AppDelegate.swift    # Window management, IPC server, startup
│   │   │   ├── SessionService.swift # Session CRUD, orphan detection
│   │   │   ├── IssueTracker.swift   # GitHub/GitLab polling (60s interval)
│   │   │   └── Scaffolder.swift     # First-run directory setup
│   │   └── Resources/
│   │       ├── AppIcon.png
│   │       └── CorveilBrandmark.png
│   └── RmIdeCLI/          # ride CLI target
│       └── RmIdeCLI.swift
├── Packages/
│   ├── RmCore/             # Data models, AppState (observable)
│   ├── RmUI/               # SwiftUI views, Corveil theme
│   ├── RmTerminal/         # Ghostty terminal surface management
│   ├── RmGit/              # Git operations
│   ├── RmProvider/         # GitHub/GitLab provider abstraction
│   ├── RmPersistence/      # JSON store, config persistence
│   ├── RmClaude/           # Claude binary resolution
│   └── RmIPC/              # Unix socket RPC protocol
├── Frameworks/              # Built GhosttyKit (gitignored)
├── vendor/ghostty/          # Ghostty submodule
├── scripts/
│   ├── build-ghostty.sh     # Builds GhosttyKit from source
│   └── bundle.sh            # Creates .app bundle
└── skills/
    └── ride-workspace/
        └── SKILL.md         # Claude Code skill for workspace setup
```

### Key Components

| Component | Description |
|-----------|-------------|
| **AppDelegate** | Initializes the app, creates the main window, starts the IPC socket server and issue tracker |
| **SessionService** | CRUD for sessions/worktrees/terminals, terminal readiness tracking, orphan detection |
| **IssueTracker** | Polls GitHub/GitLab every 60 seconds for assigned issues, PR status, project board status, auto-completes sessions on merged PRs |
| **TerminalManager** | Manages Ghostty terminal surfaces with lifecycle tracking (uninitialized → surfaceCreated → shellReady → claudeLaunched) |
| **SocketServer** | Unix socket at `$TMPDIR/ride.sock` — receives JSON-RPC commands from the `ride` CLI |

### Data Flow

```
User clicks session tab
  → SwiftUI renders TerminalSurfaceView
  → GhosttySurfaceView.createSurface() spawns shell
  → TerminalManager detects readiness (2s after surface creation)
  → Auto-sends `claude --continue` to resume Claude Code
  → Status dot turns green
```

```
User invokes /ride-workspace in Manager tab
  → Claude Code runs ride CLI commands via Unix socket
  → ride new-session → ride add-worktree → ride new-terminal
  → App creates session, registers worktree, spawns terminal
  → User clicks new session tab → Claude launches automatically
```

## Configuration

### File Locations

| Path | Purpose |
|------|---------|
| `~/Library/Application Support/rm-ai-ide/devroot` | Pointer to development root directory |
| `~/Library/Application Support/rm-ai-ide/store.json` | Persisted sessions, worktrees, links, terminals |
| `{devRoot}/.claude/config.json` | Workspace configuration |
| `{devRoot}/.claude/CLAUDE.md` | Manager tab context (ride CLI reference) |
| `{devRoot}/.claude/settings.json` | Claude Code permission settings |
| `{devRoot}/.claude/skills/ride-workspace/SKILL.md` | Workspace setup skill |

### Workspace Configuration

`{devRoot}/.claude/config.json`:

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
    "excludeDirs": ["node_modules", ".git", "vendor", "dist", "build", "target"]
  }
}
```

### Directory Structure

The app expects repos organized under workspace folders:

```
~/Dev/                          # Development root
├── RadiusMethod/               # Workspace (GitHub)
│   ├── citadel/                # Main repo checkout
│   ├── citadel-134-sensor/     # Worktree for issue #134
│   └── citadel-209-review/     # Worktree for issue #209
└── MyGitLab/                # Workspace (GitLab)
    ├── my-project/
    └── overrides/
```

Worktrees are created at the same level as the main repo, **not** in subdirectories.

## Usage

### The Sidebar

- **Tickets** — Shows assigned issues grouped by project board status (Backlog, Ready, In Progress, In Review, Done in last 24h). Click to open the full ticket board.
- **Manager** — A persistent Claude Code terminal for orchestrating work. Use `/ride-workspace` here to create new sessions.
- **Active Sessions** — One per work context. Shows repo, branch, issue/PR badges with pipeline and review status.
- **Completed Sessions** — Sessions whose PRs have been merged or issues closed.

### Creating a Session

In the Manager tab, tell Claude Code what you want to work on:

```
/ride-workspace https://github.com/org/repo/issues/123
```

Or use natural language:

```
/ride-workspace "add authentication to the citadel API"
```

This will:
1. Create a git worktree with a feature branch
2. Create a session with ticket metadata
3. Launch Claude Code in plan mode with the issue context
4. Auto-assign the issue and set its project status to "In Progress"

### Session Lifecycle

| State | Trigger | Sidebar |
|-------|---------|---------|
| Active | Created via `/ride-workspace` | Green dot (or gray/yellow/blue during terminal init) |
| Completed | PR merged or issue closed (auto-detected), or manual "Mark as Completed" | Gold checkmark |
| Archived | Manual | Gray archive icon |

### Terminal Readiness

When you click a session tab, the terminal goes through:
1. **Gray dot** — Terminal not yet initialized
2. **Yellow dot** — Surface created, shell starting
3. **Blue dot** — Shell ready
4. **Green dot** — `claude --continue` sent, Claude is running

A loading overlay shows during initialization and disappears when Claude launches.

## ride CLI Reference

The `ride` CLI communicates with the running app via Unix socket. The app must be running for commands to work.

### Session Commands

```bash
ride new-session --name "feature-name"
ride rename-session --session <uuid> "new-name"
ride select-session --session <uuid>
ride list-sessions
ride get-session --session <uuid>
ride set-status --session <uuid> active|completed|archived
ride delete-session --session <uuid>
```

### Metadata Commands

```bash
ride set-ticket --session <uuid> --url "..." [--title "..."] [--number N]
ride add-link --session <uuid> --label "Issue" --url "..." --type ticket|pr|repo|custom
ride list-links --session <uuid>
```

### Worktree Commands

```bash
ride add-worktree --session <uuid> \
  --repo "repo-name" \
  --repo-path "/path/to/main/repo" \
  --path "/path/to/worktree" \
  --branch "feature/name" \
  [--workspace "WorkspaceName"] \
  [--primary]
ride list-worktrees --session <uuid>
```

### Terminal Commands

```bash
ride new-terminal --session <uuid> --cwd "/path" [--name "Claude Code"]
ride list-terminals --session <uuid>
ride send --session <uuid> --terminal <uuid> "text to send\n"
```

All commands return JSON. The `ride send` command converts `\n` in the text to Enter keypresses.

## Features

### Ticket Board
- Pipeline view showing issues by project board status
- Click a status to filter the list
- "Start Working" button creates a workspace directly from an issue
- Issues linked to active sessions show a navigation button

### PR Status Tracking
- Pipeline checks (passing/failing/pending)
- Review status (approved/changes requested/needs review)
- Merge readiness (mergeable/conflicting/merged)
- Purple badge with checkmark for merged PRs

### Auto-Complete
- Sessions automatically move to "Completed" when their linked PR is merged or issue is closed
- Checked every 60 seconds during the issue polling cycle

### Orphan Recovery
- On startup, scans git worktrees across all repos
- Worktrees not tracked in the store are automatically recovered as sessions
- Fetches ticket metadata and PR links from GitHub for recovered sessions

### Safe Deletion
- Deleting a session on a protected branch (main, master, develop) only removes the session metadata — the repo folder and branch are preserved
- The delete confirmation dialog reflects this, showing "Remove Session" instead of "Delete Everything"

## Development

### Adding a New Package

1. Create the package under `Packages/`
2. Add it to the root `Package.swift` dependencies and target
3. Import in the targets that need it

### Debugging

The app logs diagnostic information to stderr:
- `[TerminalManager]` — Surface creation and readiness transitions
- `[SessionService]` — Orphan detection and session lifecycle
- `[IssueTracker]` — GitHub API errors, scope issues
- `[JSONStore]` — Decode failures (store data loss prevention)
- `[Ghostty]` — Surface creation success/failure

Run with log filtering:
```bash
.build/debug/RmAiIde 2>&1 | grep "\[TerminalManager\]\|\[SessionService\]"
```

## License

Proprietary — Radius Method, Inc.
