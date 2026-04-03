import SwiftUI
import RmCore

/// Settings panel accessible via Cmd+,
public struct SettingsView: View {
    @State var devRoot: String
    @State var config: AppConfig
    @State private var isAddingWorkspace = false
    @State private var editingWorkspace: WorkspaceInfo?

    public var onSave: ((String, AppConfig) -> Void)?
    public var onRescaffold: ((String) -> Void)?

    public init(devRoot: String, config: AppConfig,
                onSave: ((String, AppConfig) -> Void)? = nil,
                onRescaffold: ((String) -> Void)? = nil) {
        self._devRoot = State(initialValue: devRoot)
        self._config = State(initialValue: config)
        self.onSave = onSave
        self.onRescaffold = onRescaffold
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            workspacesTab
                .tabItem { Label("Workspaces", systemImage: "rectangle.stack") }
            NotificationSettingsView(settings: $config.notifications)
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 520, height: 480)
        .sheet(isPresented: $isAddingWorkspace) {
            WorkspaceEditorView(workspace: nil) { ws in
                config.workspaces.append(ws)
                save()
            }
        }
        .sheet(item: $editingWorkspace) { ws in
            WorkspaceEditorView(workspace: ws) { updated in
                if let idx = config.workspaces.firstIndex(where: { $0.id == updated.id }) {
                    config.workspaces[idx] = updated
                    save()
                }
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
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
            }
        }
        .padding()
    }

    // MARK: - Workspaces Tab

    private var workspacesTab: some View {
        VStack {
            List {
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
                                .font(.caption)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            config.workspaces.removeAll { $0.id == ws.id }
                            save()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Spacer()
                Button {
                    isAddingWorkspace = true
                } label: {
                    Label("Add Workspace", systemImage: "plus")
                }
            }
            .padding()
        }
    }

    private func save() {
        onSave?(devRoot, config)
    }
}

// MARK: - Workspace Editor

public struct WorkspaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var provider: String
    @State private var host: String
    @State private var alwaysIncludeText: String

    private let existingID: UUID?
    private let onSave: (WorkspaceInfo) -> Void

    public init(workspace: WorkspaceInfo?, onSave: @escaping (WorkspaceInfo) -> Void) {
        self.existingID = workspace?.id
        self._name = State(initialValue: workspace?.name ?? "")
        self._provider = State(initialValue: workspace?.provider ?? "github")
        self._host = State(initialValue: workspace?.host ?? "")
        self._alwaysIncludeText = State(initialValue: workspace?.alwaysInclude.joined(separator: ", ") ?? "")
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(existingID == nil ? "Add Workspace" : "Edit Workspace")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Name (e.g., RadiusMethod)", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Provider", selection: $provider) {
                Text("GitHub").tag("github")
                Text("GitLab").tag("gitlab")
            }
            .pickerStyle(.segmented)

            if provider == "gitlab" {
                TextField("GitLab host (e.g., gitlab.example.com)", text: $host)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Always include repos (comma-separated)", text: $alwaysIncludeText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    let alwaysInclude = alwaysIncludeText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    let ws = WorkspaceInfo(
                        id: existingID ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        provider: provider,
                        cli: provider == "github" ? "gh" : "glab",
                        host: provider == "gitlab" && !host.isEmpty ? host : nil,
                        alwaysInclude: alwaysInclude
                    )
                    onSave(ws)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
