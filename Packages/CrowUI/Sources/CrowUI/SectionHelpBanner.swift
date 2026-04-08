import SwiftUI

/// A dismissible help banner that explains a section's purpose.
/// Dismissal state persists via `@AppStorage` using a per-section key.
public struct SectionHelpBanner: View {
    let description: String
    @AppStorage private var isDismissed: Bool

    public init(description: String, storageKey: String) {
        self.description = description
        self._isDismissed = AppStorage(wrappedValue: false, storageKey)
    }

    public var body: some View {
        if !isDismissed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(CorveilTheme.textMuted)
                    .accessibilityHidden(true)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(CorveilTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CorveilTheme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss help text")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CorveilTheme.bgCard)
        }
    }
}
