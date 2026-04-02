import SwiftUI

/// Corveil design tokens translated from corveil.com/styles.css
enum CorveilTheme {
    // Backgrounds
    static let bgDeep = Color(hex: 0x121416)
    static let bgSurface = Color(hex: 0x1A1D20)
    static let bgCard = Color(hex: 0x22262A)

    // Gold palette
    static let gold = Color(hex: 0xDDC482)
    static let goldDark = Color(hex: 0xB38E46)

    // Borders
    static let borderSubtle = Color(hex: 0xDDC482, opacity: 0.12)
    static let borderStrong = Color(hex: 0xDDC482, opacity: 0.25)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xA8A9AE)
    static let textMuted = Color(hex: 0x6B6D72)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
