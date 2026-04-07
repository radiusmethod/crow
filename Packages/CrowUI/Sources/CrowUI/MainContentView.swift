import SwiftUI
import CrowCore

/// Main content view using NavigationSplitView.
public struct MainContentView: View {
    @Bindable var appState: AppState

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
            } else if appState.selectedSessionID == AppState.allowListSessionID {
                AllowListView(appState: appState)
            } else if appState.selectedSessionID == AppState.reviewBoardSessionID {
                ReviewBoardView(appState: appState)
            } else if appState.selectedSessionID == AppState.globalTerminalSessionID {
                GlobalTerminalView(appState: appState)
            } else if let session = appState.selectedSession {
                SessionDetailView(session: session, appState: appState)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "terminal",
                    description: Text("Select a session from the sidebar or create a new one.")
                )
            }
        }
    }
}
