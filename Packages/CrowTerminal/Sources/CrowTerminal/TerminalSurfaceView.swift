import SwiftUI
import AppKit
import CrowCore
import GhosttyKit

/// SwiftUI wrapper that reuses a persistent `GhosttySurfaceView`.
///
/// For `.ghostty` terminals: fetches a per-terminal surface from
/// `TerminalManager.shared` (legacy path; one surface per terminal).
///
/// For `.tmux` terminals (#198 rollout): all visible-tab views share the
/// same `GhosttySurfaceView` from `TmuxBackend.shared.cockpitSurface()`.
/// Switching tabs re-parents the same NSView and fires
/// `TmuxBackend.shared.makeActive(id:)` so the attached tmux client jumps
/// to the right window. The shared-surface model means at most one tmux
/// terminal is on-screen at a time — fine today (Crow has no split view).
public struct TerminalSurfaceView: NSViewRepresentable {
    let terminalID: UUID
    let workingDirectory: String?
    let command: String?
    let backend: TerminalBackend

    public init(
        terminalID: UUID = UUID(),
        workingDirectory: String? = nil,
        command: String? = nil,
        backend: TerminalBackend = .ghostty
    ) {
        self.terminalID = terminalID
        self.workingDirectory = workingDirectory
        self.command = command
        self.backend = backend
    }

    @MainActor
    public func makeNSView(context: Context) -> NSView {
        let surface = surfaceForBackend()
        let container = NSView()
        container.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Resize after layout settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let size = container.bounds.size
            if size.width > 0 && size.height > 0 {
                surface.setFrameSize(size)
            }
            surface.window?.makeFirstResponder(surface)
        }
        // For tmux backends, switch to this terminal's window now that it's
        // about to be visible.
        if backend == .tmux {
            try? TmuxBackend.shared.makeActive(id: terminalID)
        }
        return container
    }

    /// Re-parent the surface if SwiftUI replaced the container, and resize.
    /// For tmux backends, also fire makeActive — this is the "tab switched
    /// to a different tmux terminal" hook in the shared-surface model.
    @MainActor
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let surface = existingSurfaceForBackend() else { return }

        if backend == .tmux {
            try? TmuxBackend.shared.makeActive(id: terminalID)
        }

        if surface.superview !== nsView {
            surface.removeFromSuperview()
            nsView.addSubview(surface)
            surface.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                surface.topAnchor.constraint(equalTo: nsView.topAnchor),
                surface.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let size = nsView.bounds.size
                if size.width > 0 && size.height > 0 {
                    surface.setFrameSize(size)
                }
                surface.window?.makeFirstResponder(surface)
            }
        }
    }

    @MainActor
    private func surfaceForBackend() -> GhosttySurfaceView {
        switch backend {
        case .ghostty:
            return TerminalManager.shared.surface(
                for: terminalID,
                workingDirectory: workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
                command: command
            )
        case .tmux:
            // The cockpit surface is created lazily on first call; subsequent
            // call sites (other tabs) get the same NSView.
            do {
                return try TmuxBackend.shared.cockpitSurface()
            } catch {
                NSLog("[TerminalSurfaceView] tmux cockpitSurface failed: \(error). Falling back to per-terminal Ghostty.")
                return TerminalManager.shared.surface(
                    for: terminalID,
                    workingDirectory: workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
                    command: command
                )
            }
        }
    }

    @MainActor
    private func existingSurfaceForBackend() -> GhosttySurfaceView? {
        switch backend {
        case .ghostty:
            return TerminalManager.shared.existingSurface(for: terminalID)
        case .tmux:
            return try? TmuxBackend.shared.cockpitSurface()
        }
    }
}
