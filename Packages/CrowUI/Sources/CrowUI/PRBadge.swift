import SwiftUI
import CrowCore

// MARK: - PR Status Extensions

extension PRStatus.CheckStatus {
    /// SF Symbol name for this check status.
    var icon: String {
        switch self {
        case .passing: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .unknown: "questionmark.circle"
        }
    }

    /// Canonical UI color for this check status.
    var color: Color {
        switch self {
        case .passing: .green
        case .failing: .red
        case .pending: .orange
        case .unknown: CorveilTheme.textMuted
        }
    }

    /// Short human-readable label.
    var label: String {
        switch self {
        case .passing: "Checks pass"
        case .failing: "Checks failing"
        case .pending: "Checks running"
        case .unknown: "No checks"
        }
    }
}

extension PRStatus.ReviewStatus {
    /// SF Symbol name for this review status.
    var icon: String {
        switch self {
        case .approved: "person.crop.circle.badge.checkmark"
        case .changesRequested: "person.crop.circle.badge.exclamationmark"
        case .reviewRequired: "person.crop.circle.badge.clock"
        case .unknown: "person.crop.circle"
        }
    }

    /// Canonical UI color for this review status.
    var color: Color {
        switch self {
        case .approved: .green
        case .changesRequested: .red
        case .reviewRequired: .orange
        case .unknown: CorveilTheme.textMuted
        }
    }

    /// Short human-readable label.
    var label: String {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .reviewRequired: "Needs review"
        case .unknown: "No reviews"
        }
    }
}

// MARK: - PR Badge (Compact)

/// Compact PR badge with status indicators for pipeline, review, and merge readiness.
/// Used in sidebar session rows.
struct PRBadge: View {
    let label: String
    let status: PRStatus?

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)

            if let status {
                if status.isMerged {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.purple)
                } else {
                    Image(systemName: status.checksPass.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(status.checksPass.color)

                    Image(systemName: status.reviewStatus.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(status.reviewStatus.color)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeBackground)
        .foregroundStyle(badgeForeground)
        .overlay(
            Capsule().strokeBorder(badgeBorder, lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        guard let status else { return label }
        if status.isMerged { return "\(label), merged" }
        return "\(label), \(status.checksPass.label), \(status.reviewStatus.label)"
    }

    private var badgeBackground: Color {
        guard let status else { return CorveilTheme.gold.opacity(0.15) }
        if status.isMerged { return Color.purple.opacity(0.12) }
        if status.hasBlockers { return Color.red.opacity(0.12) }
        if status.isReadyToMerge { return Color.green.opacity(0.12) }
        return CorveilTheme.gold.opacity(0.12)
    }

    private var badgeForeground: Color {
        guard let status else { return CorveilTheme.gold }
        if status.isMerged { return .purple }
        if status.hasBlockers { return .red }
        if status.isReadyToMerge { return .green }
        return CorveilTheme.gold
    }

    private var badgeBorder: Color {
        guard let status else { return CorveilTheme.goldDark.opacity(0.3) }
        if status.isMerged { return Color.purple.opacity(0.3) }
        if status.hasBlockers { return .red.opacity(0.3) }
        if status.isReadyToMerge { return .green.opacity(0.3) }
        return CorveilTheme.goldDark.opacity(0.3)
    }
}

// MARK: - PR Status Detail (Expanded)

/// Expanded PR status display for the session detail header, with text labels.
struct PRStatusDetail: View {
    let status: PRStatus

    var body: some View {
        if status.isMerged {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("Merged")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        } else {
            HStack(spacing: 8) {
                // Pipeline checks
                HStack(spacing: 3) {
                    Image(systemName: status.checksPass.icon)
                        .font(.caption2)
                        .foregroundStyle(status.checksPass.color)
                    Text(checksLabel)
                        .font(.caption2)
                        .foregroundStyle(status.checksPass.color)
                }

                // Review status
                HStack(spacing: 3) {
                    Image(systemName: status.reviewStatus.icon)
                        .font(.caption2)
                        .foregroundStyle(status.reviewStatus.color)
                    Text(status.reviewStatus.label)
                        .font(.caption2)
                        .foregroundStyle(status.reviewStatus.color)
                }

                // Merge conflicts
                if status.mergeable == .conflicting {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("Conflicts")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var checksLabel: String {
        if status.checksPass == .failing && !status.failedCheckNames.isEmpty {
            return "\(status.failedCheckNames.count) failing"
        }
        return status.checksPass.label
    }
}
