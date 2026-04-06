# Changelog

All notable changes to Crow will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-04-05

Initial open-source release of Crow.

### Added

- Native macOS application with ticket board, terminal management, and GitHub integration
- Embedded Ghostty terminal with multi-tab support per session
- Session-based workflow management (create, pause, resume, archive)
- Git worktree management with orphan worktree recovery
- GitHub integration with PR status tracking and project board sync
- "In Review" button to update GitHub Project status from the app
- Claude Code hook event system for automatic session activity tracking
- Notification system with configurable sounds and macOS notifications
- "Open in VS Code" and "Open Terminal" buttons for session worktrees
- CLI tool (`crow`) for session, terminal, and metadata management via Unix socket RPC
- `crow setup` command for first-time configuration
- Makefile for build automation (`make build`, `make release`)
- Corveil branding with styled About page showing git commit SHA
- Configurable sidebar with option to hide subtitle lines
- Ticket page redesign with search, sort, and done state filtering
- Claude Code allow list aggregation and promotion across worktrees
- Comprehensive README with setup guide, architecture docs, and CLI reference
- Contributing guide, issue templates, and PR template
- Security audit and open-source readiness documentation

### Fixed

- Ghostty terminal mouse position offset
- UI blocking during GitHub polling and terminal resize on display change
- Merged PR status not detected on app restart
- Crash when reopening About or Settings window
- Disconnected hooks for CLI-created sessions
