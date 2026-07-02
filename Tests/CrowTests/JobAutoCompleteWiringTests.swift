import Foundation
import Testing
import CrowCore
import CrowPersistence
@testable import Crow

/// Integration coverage for job auto-completion (CROW-561): drives the real
/// `JobScheduler.checkFinishedRuns` against a real `SessionService` + `AppState`,
/// so the *wiring* is exercised — that the tick reads the live `activityState`,
/// `terminalReadiness`, and session `status`, and actually flips + persists the
/// session via `completeSession`. The pure decision matrix is covered separately
/// by `JobFinishDecisionTests`.
@Suite("Job auto-complete wiring (CROW-561)")
@MainActor
struct JobAutoCompleteWiringTests {

    /// Build a scheduler wired to a fresh AppState + temp-dir store, with one
    /// active `.job` session, a launched terminal, and a watched run whose
    /// prompts were delivered long enough ago to be past the settle window.
    private func makeFixture(
        kind: SessionKind = .job,
        activity: AgentActivityState
    ) -> (JobScheduler, AppState, SessionService, UUID) {
        let appState = AppState()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crow-jobcomplete-\(UUID().uuidString)")
        let service = SessionService(store: JSONStore(directory: tmp), appState: appState)
        let scheduler = JobScheduler(appState: appState, sessionService: service)

        let sessionID = UUID()
        let terminalID = UUID()
        appState.sessions = [Session(id: sessionID, name: "job-x", kind: kind)]
        appState.terminalReadiness[terminalID] = .agentLaunched
        appState.hookState(for: sessionID).activityState = activity
        // Delivered 60s ago → well past the 20s settle window.
        scheduler.beginWatching(
            sessionID: sessionID,
            terminalID: terminalID,
            startedAt: Date().addingTimeInterval(-120),
            promptsDeliveredAt: Date().addingTimeInterval(-60)
        )
        return (scheduler, appState, service, sessionID)
    }

    private func status(_ appState: AppState, _ id: UUID) -> SessionStatus? {
        appState.sessions.first { $0.id == id }?.status
    }

    @Test func doneJobIsCompletedAndUnwatched() {
        let (scheduler, appState, _, id) = makeFixture(activity: .done)
        scheduler.checkFinishedRuns(now: Date())
        #expect(status(appState, id) == .completed)
        #expect(!scheduler.isWatching(sessionID: id))
    }

    @Test func waitingJobStaysActiveAndWatched() {
        // Awaiting-input / errored (`.waiting`) must surface, not complete —
        // and stay watched so it can still complete if it later reaches `.done`.
        let (scheduler, appState, _, id) = makeFixture(activity: .waiting)
        scheduler.checkFinishedRuns(now: Date())
        #expect(status(appState, id) == .active)
        #expect(scheduler.isWatching(sessionID: id))
    }

    @Test func idleJobStaysActive() {
        // `.idle` is the never-started default (e.g. a failed launch that never
        // emitted a hook event) — must not be swept to completed.
        let (scheduler, appState, _, id) = makeFixture(activity: .idle)
        scheduler.checkFinishedRuns(now: Date())
        #expect(status(appState, id) == .active)
        #expect(scheduler.isWatching(sessionID: id))
    }

    @Test func workingJobStaysActive() {
        let (scheduler, appState, _, id) = makeFixture(activity: .working)
        scheduler.checkFinishedRuns(now: Date())
        #expect(status(appState, id) == .active)
        #expect(scheduler.isWatching(sessionID: id))
    }

    @Test func managerSessionIsNeverCompleted() {
        // Defensive: even if a manager were somehow watched, `completeSession`'s
        // guard keeps it active. (Jobs are `.job` kind and never watched as one.)
        let (scheduler, appState, _, id) = makeFixture(kind: .manager, activity: .done)
        scheduler.checkFinishedRuns(now: Date())
        #expect(status(appState, id) == .active)
    }

    @Test func completionPersistsToStore() {
        // The flip must hit disk, not just in-memory AppState.
        let appState = AppState()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crow-jobcomplete-persist-\(UUID().uuidString)")
        let store = JSONStore(directory: tmp)
        let service = SessionService(store: store, appState: appState)
        let scheduler = JobScheduler(appState: appState, sessionService: service)

        let sessionID = UUID()
        let terminalID = UUID()
        let session = Session(id: sessionID, name: "job-x", kind: .job)
        appState.sessions = [session]
        // Seed the store too — in the real app `runJob` persists the session on
        // creation; `updateSessionStatus` only writes a status *change* to an
        // already-stored row.
        store.mutate { $0.sessions = [session] }
        appState.terminalReadiness[terminalID] = .agentLaunched
        appState.hookState(for: sessionID).activityState = .done
        scheduler.beginWatching(
            sessionID: sessionID,
            terminalID: terminalID,
            promptsDeliveredAt: Date().addingTimeInterval(-60)
        )

        scheduler.checkFinishedRuns(now: Date())

        // Re-open the store from disk to confirm the flip was persisted, not
        // just applied to the in-memory AppState.
        let reloaded = JSONStore(directory: tmp)
        #expect(reloaded.data.sessions.first { $0.id == sessionID }?.status == .completed)
    }
}
