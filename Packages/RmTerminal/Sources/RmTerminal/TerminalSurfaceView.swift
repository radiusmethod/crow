import SwiftUI
import AppKit
import GhosttyKit

/// Manages live terminal surfaces, keeping them alive across SwiftUI view reloads.
@MainActor
public final class TerminalManager {
    public static let shared = TerminalManager()

    private var surfaces: [UUID: GhosttySurfaceView] = [:]

    private init() {}

    public func surface(for id: UUID, workingDirectory: String, command: String? = nil) -> GhosttySurfaceView {
        if let existing = surfaces[id] { return existing }
        let view = GhosttySurfaceView(frame: .zero, workingDirectory: workingDirectory, command: command)
        surfaces[id] = view
        // Don't eagerly create the surface — it needs to be in a window first
        // so it can get the correct scale factor and size.
        // createSurface() is called in viewDidMoveToWindow.
        return view
    }

    public func existingSurface(for id: UUID) -> GhosttySurfaceView? { surfaces[id] }

    public func destroy(id: UUID) {
        if let view = surfaces.removeValue(forKey: id) { view.destroy() }
    }

    public func send(id: UUID, text: String) { surfaces[id]?.writeText(text) }

    /// Pre-create a surface and attach it briefly to a window so `viewDidMoveToWindow` fires
    /// and the Ghostty surface initializes. The view is placed off-screen and removed after init.
    public func warmSurface(for id: UUID, workingDirectory: String, command: String? = nil, in window: NSWindow) {
        let view = surface(for: id, workingDirectory: workingDirectory, command: command)
        guard !view.hasSurface else { return }  // Already initialized

        // Temporarily add to the window's content view off-screen to trigger viewDidMoveToWindow
        let container = NSView(frame: NSRect(x: -9999, y: -9999, width: 800, height: 600))
        container.addSubview(view)
        view.frame = container.bounds
        window.contentView?.addSubview(container)

        // Give it time to initialize, then remove the container (but keep the surface alive in TerminalManager)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            view.removeFromSuperview()
            container.removeFromSuperview()
        }
    }
}

/// SwiftUI wrapper that reuses a persistent GhosttySurfaceView from TerminalManager.
public struct TerminalSurfaceView: NSViewRepresentable {
    let terminalID: UUID
    let workingDirectory: String?
    let command: String?

    public init(terminalID: UUID = UUID(), workingDirectory: String? = nil, command: String? = nil) {
        self.terminalID = terminalID
        self.workingDirectory = workingDirectory
        self.command = command
    }

    @MainActor
    public func makeNSView(context: Context) -> NSView {
        let surface = TerminalManager.shared.surface(
            for: terminalID,
            workingDirectory: workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
            command: command
        )
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
        return container
    }

    @MainActor
    public func updateNSView(_ nsView: NSView, context: Context) {
        if let surface = TerminalManager.shared.existingSurface(for: terminalID),
           surface.superview !== nsView {
            surface.removeFromSuperview()
            nsView.addSubview(surface)
            surface.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                surface.topAnchor.constraint(equalTo: nsView.topAnchor),
                surface.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
            ])
        }
        // After layout settles, resize the surface and take focus
        if let surface = TerminalManager.shared.existingSurface(for: terminalID) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let size = nsView.bounds.size
                if size.width > 0 && size.height > 0 {
                    surface.setFrameSize(size)
                }
                surface.window?.makeFirstResponder(surface)
            }
        }
    }
}
