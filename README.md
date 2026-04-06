# Crow

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
git clone --recurse-submodules https://github.com/radiusmethod/crow.git
cd crow

# 2. Build the Ghostty terminal framework
./scripts/build-ghostty.sh

# 3. Build the app
swift build

# 4. Authenticate GitHub CLI
gh auth login
gh auth refresh -s read:project   # Required for project board status

# 5. Run
.build/debug/CrowApp
```

On first launch, a setup wizard guides you through choosing your development root directory and configuring workspaces.

Alternatively, configure via the CLI without launching the GUI:

```bash
.build/debug/crow setup
```

## Detailed Setup

### 1. Clone the Repository

```bash
git clone --recurse-submodules https://github.com/radiusmethod/crow.git
cd crow
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
- `CrowApp` — the main application
- `crow` — the CLI for session management

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
.build/debug/CrowApp
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
crow/
├── Sources/
│   ├── Crow/              # Main app target
│   │   ├── App/
│   │   │   ├── main.swift           # Entry point
│   │   │   ├── AppDelegate.swift    # Window management, IPC server, startup
│   │   │   ├── SessionService.swift # Session CRUD, orphan detection
│   │   │   ├── IssueTracker.swift   # GitHub/GitLab polling (60s interval)
│   │   │   └── Scaffolder.swift     # First-run directory setup
│   │   └── Resources/
│   │       ├── AppIcon.png
│   │       └── CorveilBrandmark.png
│   └── CrowCLI/            # crow CLI target
│       └── CrowCLI.swift
├── Packages/
│   ├── CrowCore/           # Data models, AppState (observable)
│   ├── CrowUI/             # SwiftUI views, Corveil theme
│   ├── CrowTerminal/       # Ghostty terminal surface management
│   ├── CrowGit/            # Git operations
│   ├── CrowProvider/       # GitHub/GitLab provider abstraction
│   ├── CrowPersistence/    # JSON store, config persistence
│   ├── CrowClaude/         # Claude binary resolution
│   └── CrowIPC/            # Unix socket RPC protocol
├── Frameworks/              # Built GhosttyKit (gitignored)
├── vendor/ghostty/          # Ghostty submodule
├── scripts/
│   ├── build-ghostty.sh     # Builds GhosttyKit from source
│   └── bundle.sh            # Creates .app bundle
└── skills/
    └── crow-workspace/
        └── SKILL.md         # Claude Code skill for workspace setup
```

### Key Components

| Component | Description |
|-----------|-------------|
| **AppDelegate** | Initializes the app, creates the main window, starts the IPC socket server and issue tracker |
| **SessionService** | CRUD for sessions/worktrees/terminals, terminal readiness tracking, orphan detection |
| **IssueTracker** | Polls GitHub/GitLab every 60 seconds for assigned issues, PR status, project board status, auto-completes sessions on merged PRs |
| **TerminalManager** | Manages Ghostty terminal surfaces with lifecycle tracking (uninitialized → surfaceCreated → shellReady → claudeLaunched) |
| **SocketServer** | Unix socket at `~/.local/share/crow/crow.sock` — receives JSON-RPC commands from the `crow` CLI |

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
User invokes /crow-workspace in Manager tab
  → Claude Code runs crow CLI commands via Unix socket
  → crow new-session → crow add-worktree → crow new-terminal
  → App creates session, registers worktree, spawns terminal
  → User clicks new session tab → Claude launches automatically
```

## Configuration

### File Locations

| Path | Purpose |
|------|---------|
| `~/Library/Application Support/crow/devroot` | Pointer to development root directory |
| `~/Library/Application Support/crow/store.json` | Persisted sessions, worktrees, links, terminals |
| `{devRoot}/.claude/config.json` | Workspace configuration |
| `{devRoot}/.claude/CLAUDE.md` | Manager tab context (crow CLI reference) |
| `{devRoot}/.claude/settings.json` | Claude Code permission settings |
| `{devRoot}/.claude/skills/crow-workspace/SKILL.md` | Workspace setup skill |

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

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CROW_SOCKET` | Override the Unix socket path for CLI ↔ App IPC | `~/.local/share/crow/crow.sock` |
| `TMPDIR` | Temporary file directory (used by the terminal subsystem) | System default |
| `GITLAB_HOST` | GitLab instance hostname (set automatically per workspace config) | — |

## Usage

### The Sidebar

- **Tickets** — Shows assigned issues grouped by project board status (Backlog, Ready, In Progress, In Review, Done in last 24h). Click to open the full ticket board.
- **Manager** — A persistent Claude Code terminal for orchestrating work. Use `/crow-workspace` here to create new sessions.
- **Active Sessions** — One per work context. Shows repo, branch, issue/PR badges with pipeline and review status.
- **Completed Sessions** — Sessions whose PRs have been merged or issues closed.

### Creating a Session

In the Manager tab, tell Claude Code what you want to work on:

```
/crow-workspace https://github.com/org/repo/issues/123
```

Or use natural language:

```
/crow-workspace "add authentication to the citadel API"
```

This will:
1. Create a git worktree with a feature branch
2. Create a session with ticket metadata
3. Launch Claude Code in plan mode with the issue context
4. Auto-assign the issue and set its project status to "In Progress"

### Session Lifecycle

| State | Trigger | Sidebar |
|-------|---------|---------|
| Active | Created via `/crow-workspace` | Green dot (or gray/yellow/blue during terminal init) |
| Completed | PR merged or issue closed (auto-detected), or manual "Mark as Completed" | Gold checkmark |
| Archived | Manual | Gray archive icon |

### Terminal Readiness

When you click a session tab, the terminal goes through:
1. **Gray dot** — Terminal not yet initialized
2. **Yellow dot** — Surface created, shell starting
3. **Blue dot** — Shell ready
4. **Green dot** — `claude --continue` sent, Claude is running

A loading overlay shows during initialization and disappears when Claude launches.

## crow CLI Reference

The `crow` CLI communicates with the running app via Unix socket. The app must be running for commands to work.

### Session Commands

```bash
crow new-session --name "feature-name"
crow rename-session --session <uuid> "new-name"
crow select-session --session <uuid>
crow list-sessions
crow get-session --session <uuid>
crow set-status --session <uuid> active|paused|inReview|completed|archived
crow delete-session --session <uuid>
```

### Metadata Commands

```bash
crow set-ticket --session <uuid> --url "..." [--title "..."] [--number N]
crow add-link --session <uuid> --label "Issue" --url "..." --type ticket|pr|repo|custom
crow list-links --session <uuid>
```

### Worktree Commands

```bash
crow add-worktree --session <uuid> \
  --repo "repo-name" \
  --repo-path "/path/to/main/repo" \
  --path "/path/to/worktree" \
  --branch "feature/name" \
  [--primary]
crow list-worktrees --session <uuid>
```

### Terminal Commands

```bash
crow new-terminal --session <uuid> --cwd "/path" [--name "Claude Code"]
crow list-terminals --session <uuid>
crow send --session <uuid> --terminal <uuid> "text to send\n"
```

All commands return JSON. The `crow send` command converts `\n` in the text to Enter keypresses.

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

### Testing

```bash
swift test        # or: mise test
```

Tests use the [Swift Testing](https://developer.apple.com/documentation/testing/) framework (`@Test` macros). Test files are under `Packages/*/Tests/`.

### Debugging

The app logs diagnostic information to stderr:
- `[TerminalManager]` — Surface creation and readiness transitions
- `[SessionService]` — Orphan detection and session lifecycle
- `[IssueTracker]` — GitHub API errors, scope issues
- `[JSONStore]` — Decode failures (store data loss prevention)
- `[Ghostty]` — Surface creation success/failure

Run with log filtering:
```bash
.build/debug/CrowApp 2>&1 | grep "\[TerminalManager\]\|\[SessionService\]"
```

## Troubleshooting

### Build Issues

| Problem | Solution |
|---------|----------|
| `zig` not found | Install with `brew install zig` or from [ziglang.org](https://ziglang.org/download/) |
| Zig version mismatch | Version 0.15.2 is required. Check with `zig version` |
| Metal toolchain not found | Run `xcodebuild -downloadComponent MetalToolchain` |
| Ghostty submodule missing | Run `git submodule update --init vendor/ghostty` |
| Swift build fails with linker errors | Ensure GhosttyKit is built first: `./scripts/build-ghostty.sh` |

### Runtime Issues

| Problem | Solution |
|---------|----------|
| `crow` CLI: "Connection refused" | The Crow app must be running — the CLI communicates via Unix socket |
| GitHub API errors / empty responses | Check auth: `gh auth status`. Add project scope: `gh auth refresh -s read:project` |
| Terminal not starting | Check stderr logs for `[TerminalManager]` or `[Ghostty]` messages |
| Issue tracker shows no tickets | Verify `gh auth status` shows `repo`, `read:org`, `read:project` scopes |

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting bugs, suggesting features, and submitting pull requests.

## Releases

Official releases are signed and notarized via GitHub Actions. Download the latest DMG from the [Releases](https://github.com/radiusmethod/crow/releases) page — it will install without Gatekeeper warnings.

**Building from source:** Code signing is only required for distribution. Developers building from source do not need a signing certificate — `make build` and `make release` produce unsigned but fully functional builds. If macOS quarantines an unsigned .app, remove it with:

```bash
xattr -cr Crow.app
```

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.
