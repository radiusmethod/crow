import SwiftUI
import RmCore

/// PR badge with status indicators for pipeline, review, and merge readiness.
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
                    // Merged — single purple checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.purple)
                } else {
                    // Pipeline status
                    Image(systemName: checksIcon(status.checksPass))
                        .font(.system(size: 8))
                        .foregroundStyle(checksColor(status.checksPass))

                    // Review status
                    Image(systemName: reviewIcon(status.reviewStatus))
                        .font(.system(size: 8))
                        .foregroundStyle(reviewColor(status.reviewStatus))
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

    private func checksIcon(_ check: PRStatus.CheckStatus) -> String {
        switch check {
        case .passing: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func checksColor(_ check: PRStatus.CheckStatus) -> Color {
        switch check {
        case .passing: .green
        case .failing: .red
        case .pending: .orange
        case .unknown: CorveilTheme.textMuted
        }
    }

    private func reviewIcon(_ review: PRStatus.ReviewStatus) -> String {
        switch review {
        case .approved: "person.crop.circle.badge.checkmark"
        case .changesRequested: "person.crop.circle.badge.exclamationmark"
        case .reviewRequired: "person.crop.circle.badge.clock"
        case .unknown: "person.crop.circle"
        }
    }

    private func reviewColor(_ review: PRStatus.ReviewStatus) -> Color {
        switch review {
        case .approved: .green
        case .changesRequested: .red
        case .reviewRequired: .orange
        case .unknown: CorveilTheme.textMuted
        }
    }
}

/// Larger PR status display for the detail header, with text labels.
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
                // Pipeline
                HStack(spacing: 3) {
                    Image(systemName: checksIcon)
                        .font(.caption2)
                        .foregroundStyle(checksColor)
                    Text(checksLabel)
                        .font(.caption2)
                        .foregroundStyle(checksColor)
                }

                // Review
                HStack(spacing: 3) {
                Image(systemName: reviewIcon)
                    .font(.caption2)
                    .foregroundStyle(reviewColor)
                Text(reviewLabel)
                    .font(.caption2)
                    .foregroundStyle(reviewColor)
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

    private var checksIcon: String {
        switch status.checksPass {
        case .passing: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var checksColor: Color {
        switch status.checksPass {
        case .passing: .green
        case .failing: .red
        case .pending: .orange
        case .unknown: CorveilTheme.textMuted
        }
    }

    private var checksLabel: String {
        switch status.checksPass {
        case .passing: return "Checks pass"
        case .failing:
            if status.failedCheckNames.isEmpty { return "Checks failing" }
            return "\(status.failedCheckNames.count) failing"
        case .pending: return "Checks running"
        case .unknown: return "No checks"
        }
    }

    private var reviewIcon: String {
        switch status.reviewStatus {
        case .approved: "person.crop.circle.badge.checkmark"
        case .changesRequested: "person.crop.circle.badge.exclamationmark"
        case .reviewRequired: "person.crop.circle.badge.clock"
        case .unknown: "person.crop.circle"
        }
    }

    private var reviewColor: Color {
        switch status.reviewStatus {
        case .approved: .green
        case .changesRequested: .red
        case .reviewRequired: .orange
        case .unknown: CorveilTheme.textMuted
        }
    }

    private var reviewLabel: String {
        switch status.reviewStatus {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .reviewRequired: "Needs review"
        case .unknown: "No reviews"
        }
    }
}
