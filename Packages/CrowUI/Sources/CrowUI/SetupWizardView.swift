import SwiftUI
import CrowCore

/// First-run setup wizard shown when no devRoot is configured.
public struct SetupWizardView: View {
    @State private var step = 1
    @State private var devRoot: String = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Dev").path
    }()
    @State private var workspaces: [WorkspaceInfo] = []
    @State private var isAddingWorkspace = false
    @State private var errorMessage: String?

    /// Called when setup completes with devRoot and config.
    public var onComplete: ((String, AppConfig) -> Void)?

    /// Called if user wants to import from existing CMUX config.
    public var onImportCMUX: (() -> (devRoot: String, config: AppConfig)?)?

    public init(
        onComplete: ((String, AppConfig) -> Void)? = nil,
        onImportCMUX: (() -> (devRoot: String, config: AppConfig)?)? = nil
    ) {
        self.onComplete = onComplete
        self.onImportCMUX = onImportCMUX
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { s in
                    Circle()
                        .fill(s <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            switch step {
            case 1: devRootStep
            case 2: workspacesStep
            default: doneStep
            }

            Spacer()

            // Navigation
            HStack {
                if step > 1 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 3 {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 1 && devRoot.isEmpty)
                } else {
                    Button("Get Started") { completeSetup() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
        .sheet(isPresented: $isAddingWorkspace) {
            WorkspaceFormView(
                existingNames: workspaces.map(\.name)
            ) { ws in
                workspaces.append(ws)
            }
        }
    }

    // MARK: - Step 1: devRoot

    private var devRootStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Welcome to Crow")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Where do you want your development workspaces?")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Path", text: $devRoot)
                    .textFieldStyle(.roundedBorder)

                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = URL(fileURLWithPath: devRoot)
                    if panel.runModal() == .OK, let url = panel.url {
                        devRoot = url.path
                    }
                }
            }
            .padding(.horizontal, 40)

            // Import option
            if onImportCMUX != nil {
                Button("Import from existing CMUX config") {
                    if let result = onImportCMUX?() {
                        devRoot = result.devRoot
                        workspaces = result.config.workspaces
                        step = 3 // Skip to done
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Step 2: Workspaces

    private var workspacesStep: some View {
        VStack(spacing: 16) {
            Text("Add Workspace Folders")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Each workspace is a folder under your dev root containing git repos.\nFor example: MyOrg (GitHub), MyGitLab (GitLab).")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if workspaces.isEmpty {
                Text("No workspaces yet.")
                    .foregroundStyle(.tertiary)
                    .padding()
            } else {
                List {
                    ForEach(workspaces) { ws in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ws.name).fontWeight(.medium)
                                Text("\(ws.provider)\(ws.host.map { " (\($0))" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                workspaces.removeAll { $0.id == ws.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 120)
            }

            Button {
                isAddingWorkspace = true
            } label: {
                Label("Add Workspace", systemImage: "plus")
            }
        }
        .padding()
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Ready to Go")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Label(devRoot, systemImage: "folder")
                    .font(.body)
                ForEach(workspaces) { ws in
                    Label("\(ws.name) (\(ws.provider))", systemImage: "rectangle.stack")
                        .font(.caption)
                        .padding(.leading, 24)
                }
            }
            .padding()
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
    }

    // MARK: - Complete

    private func completeSetup() {
        let config = AppConfig(workspaces: workspaces)
        onComplete?(devRoot, config)
    }
}
