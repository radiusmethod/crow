import SwiftUI
import CrowCore

// MARK: - Main Allow List View

/// Full-pane view for aggregating and promoting allow-list entries.
public struct AllowListView: View {
    @Bindable var appState: AppState
    @State private var selection: Set<String> = []
    @State private var searchText = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredEntries: [AllowEntry] {
        if searchText.isEmpty { return appState.allowEntries }
        return appState.allowEntries.filter {
            $0.pattern.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var promotableSelection: Set<String> {
        selection.filter { pattern in
            appState.allowEntries.first { $0.pattern == pattern }?.isInGlobal == false
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            entryList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            appState.onLoadAllowList?()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Allow List")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CorveilTheme.gold)

            if appState.isLoadingAllowList {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Text("\(appState.allowEntries.count) entries")
                .font(.caption)
                .foregroundStyle(CorveilTheme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(CorveilTheme.bgSurface)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CorveilTheme.textMuted)
                    .font(.caption)
                TextField("Filter patterns…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(CorveilTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button {
                appState.onLoadAllowList?()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                appState.onPromoteToGlobal?(promotableSelection)
                selection = []
            } label: {
                Label("Promote to Global", systemImage: "arrow.up.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(promotableSelection.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(CorveilTheme.bgSurface)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List(filteredEntries, selection: $selection) { entry in
            AllowEntryRow(entry: entry)
                .listRowSeparator(.visible)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(CorveilTheme.bgDeep)
    }
}

// MARK: - Entry Row

struct AllowEntryRow: View {
    let entry: AllowEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.pattern)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(entry.isInGlobal ? CorveilTheme.textMuted : CorveilTheme.textPrimary)

            HStack(spacing: 6) {
                if entry.isInGlobal {
                    SourceBadge(label: "Global", color: .green)
                }
                if entry.isInWorkspace {
                    SourceBadge(label: "Workspace", color: CorveilTheme.gold)
                }
                ForEach(entry.worktreeSessionNames, id: \.self) { name in
                    SourceBadge(label: name, color: .blue)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(entry.isInGlobal ? 0.6 : 1.0)
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .overlay(
                Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }
}
