import Foundation

/// A user-triggered next step that maps 1:1 to a PR status badge on the
/// session card. Selecting the action injects a deterministic prompt into
/// the session's managed Claude Code terminal so the user can act without
/// switching focus into the session.
///
/// Mirrors the auto-respond pipeline (`AutoRespondCoordinator`) but bypasses
/// the per-toggle `AutoRespondSettings` gate — the user clicked, so intent
/// is explicit.
public enum QuickAction: String, Sendable, Equatable {
    /// `mergeable == .conflicting` — rebase onto base and resolve conflicts.
    case fixConflicts
    /// `reviewStatus == .changesRequested` — read review feedback and fix.
    case addressChanges
    /// `checksPass == .failing` — investigate failing checks and fix.
    case fixChecks
    /// `isReadyToMerge` — merge the PR.
    case mergePR
}
