import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Set app icon from bundled resource
if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
   let iconImage = NSImage(contentsOf: iconURL) {
    app.applicationIconImage = iconImage
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
