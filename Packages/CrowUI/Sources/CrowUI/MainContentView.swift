import SwiftUI
import CrowCore

/// Main content view using NavigationSplitView.
public struct MainContentView: View {
    @Bindable var appState: AppState

    /// Cache the last valid session to prevent "No Session Selected" flicker
    /// when @Observable mutations (hook events, terminal readiness) cause
    /// SwiftUI's List(selection:) to transiently nil out selectedSessionID.
    @State private var lastSession: Session?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SessionListView(appState: appState)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } detail: {
            if appState.selectedSessionID == AppState.ticketBoardSessionID {
                TicketBoardView(appState: appState)
            } else if let session = appState.selectedSession {
                SessionDetailView(session: session, appState: appState)
            } else if let cached = lastSession, appState.sessions.contains(where: { $0.id == cached.id }) {
                // Transient nil from List re-render — keep showing the last session
                SessionDetailView(session: cached, appState: appState)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "terminal",
                    description: Text("Select a session from the sidebar or create a new one.")
                )
            }
        }
        .onChange(of: appState.selectedSessionID) { _, newValue in
            if let newValue, let session = appState.sessions.first(where: { $0.id == newValue }) {
                lastSession = session
            }
        }
    }
}
