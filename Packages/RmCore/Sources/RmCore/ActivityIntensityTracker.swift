import Foundation

/// Aggregates session activity into a smoothed 0.0–1.0 intensity value
/// for driving the fire effect animation behind the branding logo.
@MainActor
@Observable
public final class ActivityIntensityTracker {
    public private(set) var intensity: Double = 0.0

    private weak var appState: AppState?
    private var timer: Timer?

    public init(appState: AppState) {
        self.appState = appState
    }

    public func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let appState else { return }

        // Step A: Working-session score
        let workingCount = appState.claudeState.values.filter { $0 == .working }.count
        let workingScore: Double = switch workingCount {
        case 0: 0.0
        case 1: 0.25
        case 2: 0.5
        case 3: 0.7
        default: 0.85
        }

        // Step B: Event-rate score (events in last 5 seconds across all sessions)
        let cutoff = Date().addingTimeInterval(-5)
        var recentEventCount = 0
        for events in appState.hookEvents.values {
            recentEventCount += events.filter { $0.timestamp > cutoff }.count
        }
        let eventScore: Double = switch recentEventCount {
        case 0: 0.0
        case 1...3: 0.15
        case 4...8: 0.3
        default: 0.5
        }

        // Step C: Raw intensity
        let raw = min(workingScore + eventScore, 1.0)

        // Step D: Exponential smoothing
        let alpha = raw > intensity ? 0.08 : 0.03
        intensity += (raw - intensity) * alpha

        // Clamp near-zero to exactly zero to avoid perpetual tiny updates
        if intensity < 0.005 { intensity = 0.0 }
    }
}
