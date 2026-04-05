import SwiftUI
import CrowCore

/// Shared form for creating or editing a workspace.
///
/// Used by both the Settings workspace editor and the Setup Wizard.
/// Handles name/provider/host/alwaysInclude fields, validation, and
/// construction of a `WorkspaceInfo` value on save.
public struct WorkspaceFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var provider: String
    @State private var host: String
    @State private var alwaysIncludeText: String

    private let existingID: UUID?
    private let existingNames: [String]
    private let onSave: (WorkspaceInfo) -> Void

    /// - Parameters:
    ///   - workspace: An existing workspace to edit, or `nil` to create a new one.
    ///   - existingNames: Names of other workspaces, used for duplicate detection.
    ///   - onSave: Called with the validated `WorkspaceInfo` when the user taps Save/Add.
    public init(
        workspace: WorkspaceInfo? = nil,
        existingNames: [String] = [],
        onSave: @escaping (WorkspaceInfo) -> Void
    ) {
        self.existingID = workspace?.id
        self._name = State(initialValue: workspace?.name ?? "")
        self._provider = State(initialValue: workspace?.provider ?? "github")
        self._host = State(initialValue: workspace?.host ?? "")
        self._alwaysIncludeText = State(initialValue: workspace?.alwaysInclude.joined(separator: ", ") ?? "")
        self.existingNames = existingNames
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameValidationError: String? {
        WorkspaceInfo.validateName(trimmedName, existingNames: existingNames)
    }

    public var body: some View {
        Form {
            Section("Workspace") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                if let error = nameValidationError, !trimmedName.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Provider", selection: $provider) {
                    Text("GitHub").tag("github")
                    Text("GitLab").tag("gitlab")
                }

                if provider == "gitlab" {
                    TextField("GitLab Host (e.g., gitlab.example.com)", text: $host)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Always Include Repos", text: $alwaysIncludeText)
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated list of repos to always show in the workspace prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(existingID != nil ? "Save" : "Add") {
                    let alwaysInclude = alwaysIncludeText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    let ws = WorkspaceInfo(
                        id: existingID ?? UUID(),
                        name: trimmedName,
                        provider: provider,
                        cli: provider == "github" ? "gh" : "glab",
                        host: provider == "gitlab" && !host.isEmpty ? host : nil,
                        alwaysInclude: alwaysInclude
                    )
                    onSave(ws)
                    dismiss()
                }
                .disabled(nameValidationError != nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}
