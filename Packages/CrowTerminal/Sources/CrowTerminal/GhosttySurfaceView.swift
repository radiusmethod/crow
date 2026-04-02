import AppKit
import GhosttyKit

/// NSView subclass that hosts a libghostty terminal surface with Metal rendering.
public final class GhosttySurfaceView: NSView {
    private var surface: ghostty_surface_t?
    private var markedTextStorage = NSMutableAttributedString()
    private var trackingArea: NSTrackingArea?

    /// Whether the Ghostty surface has been created (needs window attachment first).
    public var hasSurface: Bool { surface != nil }

    /// Called after createSurface() succeeds.
    public var onSurfaceCreated: (() -> Void)?

    /// The working directory for the shell spawned in this surface.
    public var workingDirectory: String?

    /// Command to run instead of the default shell.
    public var command: String?

    // MARK: - Initialization

    public init(frame: NSRect, workingDirectory: String? = nil, command: String? = nil) {
        self.workingDirectory = workingDirectory
        self.command = command
        super.init(frame: frame)

        wantsLayer = true
        layer?.isOpaque = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    @MainActor
    public func createSurface() {
        guard let app = GhosttyApp.shared.app else {
            NSLog("GhosttyApp not initialized")
            return
        }

        // If command contains shell expansions ($(...), backticks, etc.), wrap in bash
        var resolvedCommand = command
        if let cmd = resolvedCommand, (cmd.contains("$(") || cmd.contains("`")) {
            resolvedCommand = "/bin/bash -c \(Self.shellEscape(cmd))"
        }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        config.font_size = 0

        if let wd = workingDirectory {
            wd.withCString { ptr in
                config.working_directory = ptr
                if let cmd = resolvedCommand {
                    cmd.withCString { cmdPtr in
                        config.command = cmdPtr
                        self.surface = ghostty_surface_new(app, &config)
                    }
                } else {
                    self.surface = ghostty_surface_new(app, &config)
                }
            }
        } else if let cmd = resolvedCommand {
            cmd.withCString { cmdPtr in
                config.command = cmdPtr
                self.surface = ghostty_surface_new(app, &config)
            }
        } else {
            surface = ghostty_surface_new(app, &config)
        }

        updateTrackingAreaInternal()

        if surface != nil {
            NSLog("[Ghostty] createSurface() succeeded, hasCallback=\(onSurfaceCreated != nil)")
            onSurfaceCreated?()
        } else {
            NSLog("[Ghostty] createSurface() FAILED — surface is nil")
        }
    }

    private static func shellEscape(_ str: String) -> String {
        // Single-quote the string, escaping any internal single quotes
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - View Lifecycle

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && surface == nil {
            createSurface()
        }
        if let surface {
            ghostty_surface_set_focus(surface, window?.isKeyWindow ?? false)
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let fbFrame = convertToBacking(NSRect(origin: .zero, size: newSize))
        let xScale = fbFrame.size.width / newSize.width
        let yScale = fbFrame.size.height / newSize.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)
        ghostty_surface_set_size(surface, UInt32(fbFrame.size.width), UInt32(fbFrame.size.height))
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            layer?.contentsScale = window.backingScaleFactor
        }
        guard let surface else { return }
        let fbFrame = convertToBacking(frame)
        let xScale = fbFrame.size.width / frame.size.width
        let yScale = fbFrame.size.height / frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)
        let size = frame.size
        if size.width > 0 && size.height > 0 {
            let scaledSize = convertToBacking(size)
            ghostty_surface_set_size(surface, UInt32(scaledSize.width), UInt32(scaledSize.height))
        }
    }

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        guard let surface else { return }
        let size = frame.size
        if size.width > 0 && size.height > 0 {
            let fbFrame = convertToBacking(NSRect(origin: .zero, size: size))
            let xScale = fbFrame.size.width / size.width
            let yScale = fbFrame.size.height / size.height
            ghostty_surface_set_content_scale(surface, xScale, yScale)
            ghostty_surface_set_size(surface, UInt32(fbFrame.size.width), UInt32(fbFrame.size.height))
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingAreaInternal()
    }

    private func updateTrackingAreaInternal() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let surface { ghostty_surface_set_focus(surface, true) }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if let surface { ghostty_surface_set_focus(surface, false) }
        return result
    }

    // MARK: - Keyboard Input

    public override func keyDown(with event: NSEvent) {
        guard let surface else { return }

        // Handle Cmd+V (paste) directly
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            paste(self)
            return
        }

        // Handle Cmd+C (copy) directly
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            copy(self)
            return
        }

        // Send key press to libghostty
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.mods = translateMods(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)

        // Only set text for printable characters (not function keys, arrows, etc.)
        // macOS uses Unicode private use area F700-F7FF for function keys
        let isPrintable: Bool
        if let chars = event.characters, let scalar = chars.unicodeScalars.first {
            isPrintable = scalar.value < 0xF700 && !event.modifierFlags.contains(.command)
        } else {
            isPrintable = false
        }

        if isPrintable, let chars = event.characters {
            chars.withCString { ptr in
                key.text = ptr
                let handled = ghostty_surface_key(surface, key)
                if !handled {
                    self.interpretKeyEvents([event])
                }
            }
        } else {
            let handled = ghostty_surface_key(surface, key)
            if !handled {
                self.interpretKeyEvents([event])
            }
        }
    }

    // MARK: - Copy / Paste

    @objc public func paste(_ sender: Any?) {
        guard let surface else { return }
        let pasteboard = NSPasteboard.general
        guard let content = pasteboard.string(forType: .string) else { return }
        content.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(content.utf8.count))
        }
    }

    @objc public func copy(_ sender: Any?) {
        guard let surface else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_has_selection(surface),
              ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        if let ptr = text.text, text.text_len > 0 {
            let str = String(cString: ptr)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(str, forType: .string)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_RELEASE
        key.mods = translateMods(event.modifierFlags)
        key.keycode = UInt32(event.keyCode)
        ghostty_surface_key(surface, key)
    }

    // MARK: - Mouse Input

    public override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, translateMods(event.modifierFlags))
    }

    public override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, translateMods(event.modifierFlags))
    }

    public override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, translateMods(event.modifierFlags))
    }

    public override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let scrollMods: ghostty_input_scroll_mods_t = event.hasPreciseScrollingDeltas ? 1 : 0
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, scrollMods)
    }

    // MARK: - Programmatic Text Input

    /// Write text to the terminal's PTY input (for crow CLI `send` command).
    /// Newlines in the text trigger Enter keypresses.
    public func writeText(_ text: String) {
        guard let surface else {
            NSLog("writeText: no surface!")
            return
        }
        // Split on newlines — text goes via ghostty_surface_text,
        // newlines go via ghostty_surface_key (Enter keypress)
        let parts = text.components(separatedBy: "\n")
        for (i, part) in parts.enumerated() {
            if !part.isEmpty {
                // Send text as-is (no \r conversion)
                part.withCString { ptr in
                    ghostty_surface_text(surface, ptr, UInt(part.utf8.count))
                }
            }
            // For each \n boundary (except the last segment), send Enter
            if i < parts.count - 1 {
                // Try both approaches: \r via text AND keycode 36 via key event
                "\r".withCString { ptr in
                    ghostty_surface_text(surface, ptr, 1)
                }
                // Also send key event as backup
                var key = ghostty_input_key_s()
                key.action = GHOSTTY_ACTION_PRESS
                key.mods = ghostty_input_mods_e(rawValue: 0)
                key.keycode = 36
                ghostty_surface_key(surface, key)
                key.action = GHOSTTY_ACTION_RELEASE
                ghostty_surface_key(surface, key)
            }
        }
        NSLog("writeText: sent \(text.count) chars, \(parts.count - 1) newlines")
    }

    // MARK: - Helpers

    private func translateMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = ghostty_input_mods_e(rawValue: 0)
        if flags.contains(.shift) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SUPER.rawValue) }
        return mods
    }

    // MARK: - Cleanup

    public func destroy() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
    }
}

// MARK: - NSTextInputClient (separate extension to avoid concurrency issues)

extension GhosttySurfaceView: @preconcurrency NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface else { return }
        let str = string as? String ?? (string as? NSAttributedString)?.string ?? ""
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
        }
        markedTextStorage = NSMutableAttributedString()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let str = string as? String ?? (string as? NSAttributedString)?.string ?? ""
        markedTextStorage = NSMutableAttributedString(string: str)
        guard let surface else { return }
        str.withCString { ptr in
            ghostty_surface_preedit(surface, ptr, UInt(str.utf8.count))
        }
    }

    public func unmarkText() {
        markedTextStorage = NSMutableAttributedString()
        guard let surface else { return }
        ghostty_surface_preedit(surface, nil, 0)
    }

    public func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    public func markedRange() -> NSRange {
        markedTextStorage.length > 0 ? NSRange(location: 0, length: markedTextStorage.length) : NSRange(location: NSNotFound, length: 0)
    }
    public func hasMarkedText() -> Bool { markedTextStorage.length > 0 }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let point = convert(NSPoint(x: x, y: frame.height - y - h), to: nil)
        guard let windowPoint = window?.convertPoint(toScreen: point) else { return .zero }
        return NSRect(x: windowPoint.x, y: windowPoint.y, width: w, height: h)
    }

    public func characterIndex(for point: NSPoint) -> Int { 0 }
}
