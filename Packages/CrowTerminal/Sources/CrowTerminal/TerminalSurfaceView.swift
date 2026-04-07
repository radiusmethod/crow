import SwiftUI
import AppKit
import GhosttyKit

/// SwiftUI wrapper that reuses a persistent `GhosttySurfaceView` from `TerminalManager`.
///
/// Uses a container `NSView` with Auto Layout constraints so the surface fills
/// the available space. The surface is fetched (or created) from `TerminalManager`
/// to survive SwiftUI view identity changes.
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

    /// Re-parent the surface if SwiftUI replaced the container, and resize to fit.
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
            // After re-parenting, resize the surface and take focus
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
