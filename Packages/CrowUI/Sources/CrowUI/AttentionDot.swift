import SwiftUI

/// 8pt solid dot with a softer scaled-stroke halo. Used in the sidebar to
/// flag rows that need user attention (orange) or are actively working (green).
struct AttentionDot: View {
    let color: Color
    let accessibilityLabel: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(1.6)
            )
            .accessibilityLabel(accessibilityLabel)
    }
}
