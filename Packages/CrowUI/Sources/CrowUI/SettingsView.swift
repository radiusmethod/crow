import SwiftUI
import CrowCore

/// Settings panel accessible via Cmd+,
///
/// Three-tab interface: General (devRoot, defaults, sidebar), Workspaces (list + add/edit),
/// and Notifications (global + per-event config). Every change is persisted immediately
/// via the `onSave` callback — there is no explicit "Apply" button.
public struct SettingsView: View {
    let appState: AppState
    @State var devRoot: String
    @State var config: AppConfig
    @State private var isAddingWorkspace = false
    @State private var editingWorkspace: WorkspaceInfo?

    public var onSave: ((String, AppConfig) -> Void)?
    public var onRescaffold: ((String) -> Void)?

    public init(appState: AppState, devRoot: String, config: AppConfig,
                onSave: ((String, AppConfig) -> Void)? = nil,
                onRescaffold: ((String) -> Void)? = nil) {
        self.appState = appState
        self._devRoot = State(initialValue: devRoot)
        self._config = State(initialValue: config)
        self.onSave = onSave
        self.onRescaffold = onRescaffold
    }

    /// Names of all workspaces except the one currently being edited.
    private func otherWorkspaceNames(excluding id: UUID? = nil) -> [String] {
        config.workspaces
            .filter { $0.id != id }
            .map(\.name)
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            workspacesTab
                .tabItem { Label("Workspaces", systemImage: "rectangle.stack") }
            NotificationSettingsView(settings: $config.notifications, onSave: { save() })
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 520, height: 480)
        .sheet(isPresented: $isAddingWorkspace) {
            WorkspaceFormView(
                existingNames: otherWorkspaceNames()
            ) { ws in
                config.workspaces.append(ws)
                save()
            }
        }
        .sheet(item: $editingWorkspace) { ws in
            WorkspaceFormView(
                workspace: ws,
                existingNames: otherWorkspaceNames(excluding: ws.id)
            ) { updated in
                if let idx = config.workspaces.firstIndex(where: { $0.id == updated.id }) {
                    config.workspaces[idx] = updated
                    save()
                }
            }
        }
    }

    // MARK: - General Tab

    @ViewBuilder
    private var githubScopeWarningBanner: some View {
        if let warning = appState.githubScopeWarning {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(warning)
                    .font(.caption)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(6)
        }
    }

    private var generalTab: some View {
        Form {
            if appState.githubScopeWarning != nil {
                Section { githubScopeWarningBanner }
            }
            Section("Development Root") {
                HStack {
                    TextField("Path", text: $devRoot)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            devRoot = url.path
                            save()
                        }
                    }
                }

                Button("Re-scaffold .claude/ directory") {
                    onRescaffold?(devRoot)
                }
                .font(.caption)
            }

            Section("Defaults") {
                Picker("Default Provider", selection: $config.defaults.provider) {
                    Text("GitHub").tag("github")
                    Text("GitLab").tag("gitlab")
                }
                .onChange(of: config.defaults.provider) { _, _ in save() }

                TextField("Branch Prefix", text: $config.defaults.branchPrefix)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }

                if !ConfigDefaults.isValidBranchPrefix(config.defaults.branchPrefix) {
                    Text("Contains characters invalid in git branch names.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Sidebar") {
                Toggle("Hide session details", isOn: $config.sidebar.hideSessionDetails)
                    .onChange(of: config.sidebar.hideSessionDetails) { _, _ in save() }
                Text("Hides ticket title and repo/branch lines in sidebar rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Remote Control") {
                Toggle("Enable remote control for new sessions", isOn: $config.remoteControlEnabled)
                    .onChange(of: config.remoteControlEnabled) { _, _ in save() }
                Text("New Claude Code sessions start with --rc so you can control them from claude.ai or the Claude mobile app. Each session's name matches its Crow session name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Telemetry") {
                Toggle("Enable session analytics", isOn: $config.telemetry.enabled)
                    .onChange(of: config.telemetry.enabled) { _, _ in save() }
                Text("Collects cost, token, and tool usage metrics from Claude Code sessions via OpenTelemetry. Requires app restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("OTLP receiver port")
                    TextField("Port", value: $config.telemetry.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit { save() }
                }
                .disabled(!config.telemetry.enabled)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Workspaces Tab

    private var workspacesTab: some View {
        Form {
            Section {
                if config.workspaces.isEmpty {
                    Text("No workspaces configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(config.workspaces) { ws in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ws.name)
                                    .fontWeight(.medium)
                                HStack(spacing: 4) {
                                    Text(ws.provider)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(ws.provider == "github" ? Color.purple.opacity(0.15) : Color.orange.opacity(0.15))
                                        .clipShape(Capsule())
                                    if let host = ws.host {
                                        Text(host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                editingWorkspace = ws
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(ws.name)")

                            Button(role: .destructive) {
                                config.workspaces.removeAll { $0.id == ws.id }
                                save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(ws.name)")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Workspaces")
                    Spacer()
                    Button {
                        isAddingWorkspace = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        onSave?(devRoot, config)
    }
}
