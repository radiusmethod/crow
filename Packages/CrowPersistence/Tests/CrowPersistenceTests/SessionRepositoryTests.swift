import Foundation
import Testing
@testable import CrowPersistence
@testable import CrowCore

@Test func saveAndFind() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = JSONStore(directory: dir)
    let repo = SessionRepository(store: store)

    let session = Session(name: "find-test", status: .active, ticketURL: "https://example.com/1")
    repo.save(session)

    let found = repo.find(id: session.id)
    #expect(found != nil)
    #expect(found?.name == "find-test")
    #expect(found?.ticketURL == "https://example.com/1")
}

@Test func saveUpdatesExisting() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = JSONStore(directory: dir)
    let repo = SessionRepository(store: store)

    var session = Session(name: "original")
    repo.save(session)
    #expect(repo.all().count == 1)

    session.name = "updated"
    repo.save(session)
    #expect(repo.all().count == 1)
    #expect(repo.find(id: session.id)?.name == "updated")
}

@Test func deleteCascadesAllRelatedData() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = JSONStore(directory: dir)
    let repo = SessionRepository(store: store)

    let sessionID = UUID()
    let session = Session(id: sessionID, name: "cascade-test")
    repo.save(session)

    // Add related data directly via store
    store.mutate { data in
        data.worktrees.append(SessionWorktree(
            sessionID: sessionID, repoName: "crow", repoPath: "/repo",
            worktreePath: "/wt", branch: "feature/x"
        ))
        data.links.append(SessionLink(
            sessionID: sessionID, label: "PR", url: "https://example.com", linkType: .pr
        ))
        data.terminals.append(SessionTerminal(
            sessionID: sessionID, name: "Shell", cwd: "/wt"
        ))
    }

    // Verify data exists
    #expect(repo.worktrees(for: sessionID).count == 1)
    #expect(repo.links(for: sessionID).count == 1)
    #expect(store.data.terminals.filter { $0.sessionID == sessionID }.count == 1)

    // Delete should cascade to all related data
    repo.delete(id: sessionID)

    #expect(repo.find(id: sessionID) == nil)
    #expect(repo.worktrees(for: sessionID).isEmpty)
    #expect(repo.links(for: sessionID).isEmpty)
    #expect(store.data.terminals.filter { $0.sessionID == sessionID }.isEmpty)
}

@Test func allReturnsSessions() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = JSONStore(directory: dir)
    let repo = SessionRepository(store: store)

    repo.save(Session(name: "session-1"))
    repo.save(Session(name: "session-2"))
    repo.save(Session(name: "session-3"))

    let all = repo.all()
    #expect(all.count == 3)
    #expect(Set(all.map(\.name)) == Set(["session-1", "session-2", "session-3"]))
}

@Test func worktreesAndLinksFilterBySession() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = JSONStore(directory: dir)
    let repo = SessionRepository(store: store)

    let session1 = UUID()
    let session2 = UUID()

    store.mutate { data in
        data.worktrees.append(SessionWorktree(
            sessionID: session1, repoName: "a", repoPath: "/a",
            worktreePath: "/wt-a", branch: "feature/a"
        ))
        data.worktrees.append(SessionWorktree(
            sessionID: session2, repoName: "b", repoPath: "/b",
            worktreePath: "/wt-b", branch: "feature/b"
        ))
        data.links.append(SessionLink(
            sessionID: session1, label: "Issue", url: "https://example.com/1", linkType: .ticket
        ))
        data.links.append(SessionLink(
            sessionID: session1, label: "PR", url: "https://example.com/2", linkType: .pr
        ))
        data.links.append(SessionLink(
            sessionID: session2, label: "Repo", url: "https://example.com/3", linkType: .repo
        ))
    }

    #expect(repo.worktrees(for: session1).count == 1)
    #expect(repo.worktrees(for: session2).count == 1)
    #expect(repo.links(for: session1).count == 2)
    #expect(repo.links(for: session2).count == 1)
}
