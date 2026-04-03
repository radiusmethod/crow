import SwiftUI

struct AboutView: View {
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            // App icon
            if let iconImage = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: iconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("Crow")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Git SHA — click to copy full hash
            Button(action: copyGitSHA) {
                HStack(spacing: 4) {
                    Text(BuildInfo.gitCommitShortSHA)
                        .font(.system(.callout, design: .monospaced))
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Click to copy full commit SHA: \(BuildInfo.gitCommitSHA)")

            Text("Built \(BuildInfo.buildDate)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 4)

            Text("© \(Calendar.current.component(.year, from: Date())) Radius Method")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(width: 300)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private func copyGitSHA() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BuildInfo.gitCommitSHA, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
