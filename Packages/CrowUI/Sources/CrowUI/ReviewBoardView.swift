import SwiftUI
import CrowCore

// MARK: - Main Review Board View

/// Full-pane review board shown when the Review Board tab is selected.
public struct ReviewBoardView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            reviewBoardHeader
            Divider()
            reviewList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            // Mark all current review requests as seen
            for request in appState.reviewRequests {
                appState.seenReviewRequestIDs.insert(request.id)
            }
        }
    }

    private var reviewBoardHeader: some View {
        HStack {
            Text("Reviews")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CorveilTheme.gold)

            if appState.isLoadingReviews {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Text("\(appState.reviewRequests.count) pending")
                .font(.caption)
                .foregroundStyle(CorveilTheme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(CorveilTheme.bgSurface)
    }

    @ViewBuilder
    private var reviewList: some View {
        if appState.reviewRequests.isEmpty {
            VStack {
                Spacer().frame(height: 40)
                Image(systemName: "eye.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(CorveilTheme.textMuted)
                Text("No Pending Reviews")
                    .font(.headline)
                    .foregroundStyle(CorveilTheme.textSecondary)
                    .padding(.top, 8)
                Text("When someone requests your review on a PR, it will appear here.")
                    .font(.caption)
                    .foregroundStyle(CorveilTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(appState.reviewRequests) { request in
                ReviewRow(request: request, appState: appState)
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Review Row

struct ReviewRow: View {
    let request: ReviewRequest
    @Bindable var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(request.repo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("#\(request.prNumber)")
                        .font(.callout)
                        .fontWeight(.medium)
                    if request.isDraft {
                        draftBadge
                    }
                }
                Text(request.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("by @\(request.author)")
                        .font(.caption)
                        .foregroundStyle(CorveilTheme.textMuted)
                    Text("\u{2022}")
                        .font(.caption2)
                        .foregroundStyle(CorveilTheme.textMuted)
                    Text(request.headBranch)
                        .font(.caption)
                        .foregroundStyle(CorveilTheme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            reviewAction
        }
        .padding(.vertical, 4)
    }

    private var draftBadge: some View {
        Text("Draft")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var reviewAction: some View {
        if let sessionID = request.reviewSessionID,
           appState.sessions.contains(where: { $0.id == sessionID }) {
            Button {
                appState.selectedSessionID = sessionID
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle")
                    Text("Go to Session")
                        .lineLimit(1)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                appState.onStartReview?(request.url)
            } label: {
                Label("Start Review", systemImage: "eye.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Sidebar Row

/// Compact sidebar row showing pending review count.
public struct ReviewBoardSidebarRow: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "eye.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(CorveilTheme.gold)
                Text("Reviews")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CorveilTheme.gold)
                if appState.isLoadingReviews {
                    ProgressView()
                        .controlSize(.mini)
                }
                if appState.reviewRequests.count > 0 {
                    Text("\(appState.reviewRequests.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(unseenCount > 0 ? CorveilTheme.gold.opacity(0.2) : Color.secondary.opacity(0.15))
                        .foregroundStyle(unseenCount > 0 ? CorveilTheme.gold : CorveilTheme.textSecondary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CorveilTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(CorveilTheme.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.vertical, 2)
    }

    private var unseenCount: Int {
        appState.unseenReviewCount
    }
}
