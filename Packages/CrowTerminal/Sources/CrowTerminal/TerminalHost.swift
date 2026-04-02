// CrowTerminal placeholder — real implementation requires GhosttyKit.xcframework
// Build libghostty first: scripts/build-ghostty.sh

import Foundation

/// Protocol for terminal host implementations.
@MainActor
public protocol TerminalHost: AnyObject {
    func write(_ data: Data)
    func resize(cols: UInt16, rows: UInt16)
}
