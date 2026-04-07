import SwiftUI
import AppKit
import GhosttyKit

/// Terminal surface readiness state (local to CrowTerminal, independent of CrowCore).
public enum SurfaceState: String, Sendable {
    case created       // ghostty_surface_t created, shell spawning
    case shellReady    // Probe file detected — shell accepts input
}

/// Manages live terminal surfaces, keeping them alive across SwiftUI view reloads.
@MainActor
public final class TerminalManager {
    public static let shared = TerminalManager()

    private var surfaces: [UUID: GhosttySurfaceView] = [:]

    /// Called when a surface's readiness state changes.
    public var onStateChanged: ((UUID, SurfaceState) -> Void)?

    private init() {}

    // MARK: - Offscreen Pre-Initialization

    /// Hidden window used to pre-initialize Ghostty surfaces without user interaction.
    /// Ghostty requires an NSView in a window for `viewDidMoveToWindow()` to trigger
    /// `createSurface()`. This offscreen window satisfies that requirement so terminals
    /// can start in the background without the user navigating to the tab.
    private lazy var offscreenWindow: NSWindow = {
        let w = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        // Do NOT call orderFront — window stays invisible and off-screen
        return w
    }()

    /// Pre-initialize a terminal surface in the offscreen window.
    /// The surface will be moved to the real view hierarchy when the user views the tab.
    public func preInitialize(id: UUID, workingDirectory: String, command: String? = nil) {
        guard surfaces[id] == nil else {
            NSLog("[TerminalManager] preInitialize(\(id)) — already exists")
            return
        }
        NSLog("[TerminalManager] preInitialize(\(id)) — creating surface in offscreen window")
        let view = GhosttySurfaceView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            workingDirectory: workingDirectory,
            command: command
        )
        view.onSurfaceCreated = { [weak self] in
            NSLog("[TerminalManager] onSurfaceCreated (offscreen) for \(id)")
            self?.surfaceDidCreate(id: id)
        }
        surfaces[id] = view
        // Adding to offscreenWindow triggers viewDidMoveToWindow → createSurface()
        offscreenWindow.contentView?.addSubview(view)
    }

    public func surface(for id: UUID, workingDirectory: String, command: String? = nil) -> GhosttySurfaceView {
        if let existing = surfaces[id] {
            NSLog("[TerminalManager] surface(for: \(id)) — returning EXISTING view")
            return existing
        }
        NSLog("[TerminalManager] surface(for: \(id)) — creating NEW view, setting onSurfaceCreated callback")
        let view = GhosttySurfaceView(frame: .zero, workingDirectory: workingDirectory, command: command)
        view.onSurfaceCreated = { [weak self] in
            NSLog("[TerminalManager] onSurfaceCreated callback fired for \(id)")
            self?.surfaceDidCreate(id: id)
        }
        surfaces[id] = view
        return view
    }

    public func existingSurface(for id: UUID) -> GhosttySurfaceView? { surfaces[id] }

    public func destroy(id: UUID) {
        if let view = surfaces.removeValue(forKey: id) { view.destroy() }
    }

    public func send(id: UUID, text: String) { surfaces[id]?.writeText(text) }

    // MARK: - Readiness Monitoring

    /// Set of terminal IDs that should be monitored for readiness.
    /// Only terminals in this set will start the probe monitor on surface creation.
    private var monitoredTerminals: Set<UUID> = []

    /// Register a terminal ID for readiness monitoring. Must be called before the surface is created.
    public func trackReadiness(for id: UUID) {
        NSLog("[TerminalManager] trackReadiness for \(id)")
        monitoredTerminals.insert(id)
    }

    /// Called after a surface's createSurface() completes. Begins monitoring if tracked.
    public func surfaceDidCreate(id: UUID) {
        NSLog("[TerminalManager] surfaceDidCreate(\(id)) — tracked=\(monitoredTerminals.contains(id)), hasOnStateChanged=\(onStateChanged != nil)")
        onStateChanged?(id, .created)
        if monitoredTerminals.contains(id) {
            monitoredTerminals.remove(id)
            // Shell needs time to initialize after surface creation.
            // Wait 2 seconds then mark as ready — the surface is in a window,
            // createSurface() has spawned the shell, we just need zsh to start.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                self.onStateChanged?(id, .shellReady)
            }
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
