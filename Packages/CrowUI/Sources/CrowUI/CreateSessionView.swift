import SwiftUI
import CrowCore

/// Sheet for manually creating a new session.
/// Note: The primary way to create sessions is via `/workspace` in the Manager tab.
/// This sheet provides a simple manual fallback.
public struct CreateSessionView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("New Session")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Use /workspace in the Manager tab for full setup.\nOr create a basic session here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Session name...", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { createSession() }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") { createSession() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func createSession() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let session = Session(name: trimmed)
        appState.sessions.append(session)
        appState.selectedSessionID = session.id
        dismiss()
    }
}
