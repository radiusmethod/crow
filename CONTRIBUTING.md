# Contributing to Crow

Thank you for your interest in contributing to Crow! This guide will help you get started.

## Reporting Bugs

Open a [GitHub Issue](https://github.com/radiusmethod/crow/issues/new?template=bug_report.md) with:

- macOS version and hardware (Intel/Apple Silicon)
- Xcode and Zig versions
- Steps to reproduce
- Expected vs actual behavior
- Relevant stderr logs (see [Debugging](README.md#debugging))

## Suggesting Features

Open a [GitHub Issue](https://github.com/radiusmethod/crow/issues/new?template=feature_request.md) describing the use case and proposed solution.

## Development Setup

See [README.md](README.md#detailed-setup) for full build instructions. The short version:

```bash
git clone --recurse-submodules https://github.com/radiusmethod/crow.git
cd crow
make build
```

### Running Tests

```bash
swift test        # or: mise test
```

Tests use the Swift Testing framework (`@Test` macros).

## Code Style

- **Swift 6.0** with strict concurrency enabled
- **SwiftUI** for all views
- Follow existing patterns in the codebase
- Keep packages focused — each package under `Packages/` has a single responsibility

## Package Structure

New functionality should go in the appropriate existing package:

| Package | Scope |
|---------|-------|
| `CrowCore` | Data models, observable app state |
| `CrowUI` | SwiftUI views, theme |
| `CrowTerminal` | Ghostty terminal surface management |
| `CrowGit` | Git operations |
| `CrowProvider` | GitHub/GitLab provider abstraction |
| `CrowPersistence` | JSON store, config I/O |
| `CrowClaude` | Claude binary resolution |
| `CrowIPC` | Unix socket RPC protocol |

If a new package is needed, create it under `Packages/` and add it to the root `Package.swift`.

## Pull Requests

1. Fork the repo and create a feature branch from `main`
2. Make your changes with clear, focused commits
3. Include tests for new functionality where applicable
4. Ensure `swift test` passes
5. Open a PR with:
   - A description of what changed and why
   - A link to the related issue
   - Screenshots for UI changes

## Auto-Scaffolded Files

Crow auto-generates certain files into `{devRoot}/.claude/` on launch (see `Scaffolder.swift`):

- `CLAUDE.md` — scaffolded from the root `CLAUDE.md`
- `skills/crow-workspace/SKILL.md` — scaffolded from `Resources/crow-workspace-SKILL.md.template`
- `settings.json` — always overwritten with pre-approved permissions

**Do not edit the scaffolded copies.** Instead, modify the source files in the repository root or `Resources/` directory.
