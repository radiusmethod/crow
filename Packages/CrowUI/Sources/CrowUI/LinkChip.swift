import SwiftUI
import CrowCore

/// Clickable capsule that opens a URL (issue link, PR link, repo link).
struct LinkChip: View {
    let label: String
    let url: String
    let icon: String

    var body: some View {
        Button {
            if let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(CorveilTheme.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CorveilTheme.gold.opacity(0.1))
            .overlay(
                Capsule().strokeBorder(CorveilTheme.goldDark.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
