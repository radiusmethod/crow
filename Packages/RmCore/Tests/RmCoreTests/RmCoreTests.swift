import Foundation
import Testing
@testable import RmCore

@Test func sessionCreation() {
    let session = Session(name: "test-session")
    #expect(session.name == "test-session")
    #expect(session.status == .active)
    #expect(session.ticketURL == nil)
}

@Test func sessionStatusTransitions() {
    var session = Session(name: "test")
    #expect(session.status == .active)

    session.status = .paused
    #expect(session.status == .paused)

    session.status = .completed
    #expect(session.status == .completed)
}

@Test func workspaceConfigDecoding() throws {
    let json = """
    {
        "devRoot": "/Users/test/Dev",
        "workspaces": {
            "Org1": {"provider": "github", "cli": "gh"}
        },
        "defaults": {
            "provider": "github",
            "cli": "gh",
            "worktreePattern": "{repo}-{feature}",
            "branchPrefix": "feature/",
            "excludeDirs": ["node_modules"],
            "keywordSources": ["README.md"]
        }
    }
    """
    let config = try JSONDecoder().decode(WorkspaceConfig.self, from: json.data(using: .utf8)!)
    #expect(config.devRoot == "/Users/test/Dev")
    #expect(config.workspaces["Org1"]?.provider == "github")
    #expect(config.defaults.branchPrefix == "feature/")
}
