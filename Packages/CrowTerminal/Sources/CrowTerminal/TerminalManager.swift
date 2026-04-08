import AppKit
import Foundation
import GhosttyKit

/// Terminal surface readiness state (local to CrowTerminal, independent of CrowCore).
public enum SurfaceState: String, Sendable {
    case created       // ghostty_surface_t created, shell spawning
    case shellReady    // Shell assumed ready after startup delay
}

/// Manages live terminal surfaces, keeping them alive across SwiftUI view reloads.
///
/// Surfaces are cached by UUID so that SwiftUI's `makeNSView`/`updateNSView` cycle
/// doesn't destroy and recreate the underlying Ghostty surface on every view update.
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

    /// Return the existing surface for `id`, or create and cache a new one.
    ///
    /// The returned view is kept alive in an internal dictionary so that
    /// SwiftUI re-renders reuse the same `GhosttySurfaceView` instance.
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
    /// Only terminals in this set will start the readiness timer on surface creation.
    private var monitoredTerminals: Set<UUID> = []

    /// Register a terminal ID for readiness monitoring.
    ///
    /// Must be called **before** the surface is created so that the
    /// `surfaceDidCreate` callback knows to start the readiness timer.
    public func trackReadiness(for id: UUID) {
        NSLog("[TerminalManager] trackReadiness for \(id)")
        monitoredTerminals.insert(id)
    }

    /// Called after a surface's `createSurface()` completes. Begins readiness monitoring if tracked.
    ///
    /// For tracked (managed) terminals, waits a brief delay for the shell to initialize
    /// before reporting `.shellReady`. Non-tracked terminals only receive `.created`.
    // TODO: Replace the fixed delay with actual shell-readiness detection (e.g., probe file).
    public func surfaceDidCreate(id: UUID) {
        NSLog("[TerminalManager] surfaceDidCreate(\(id)) — tracked=\(monitoredTerminals.contains(id)), hasOnStateChanged=\(onStateChanged != nil)")
        onStateChanged?(id, .created)
        if monitoredTerminals.contains(id) {
            monitoredTerminals.remove(id)
            // Shell needs time to initialize after surface creation.
            // On app restart, multiple terminals initialize concurrently which
            // causes shell startup to take longer than a single terminal.
            // 5 seconds handles the common case; the TODO above tracks proper detection.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self else { return }
                self.onStateChanged?(id, .shellReady)
            }
        }
    }
}
