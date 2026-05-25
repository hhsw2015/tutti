import Foundation

@MainActor
final class TrialManager: ObservableObject {
    static let shared = TrialManager()

    // Fresh per process. Banner dismissals are scoped against this so the
    // trialExpired banner reappears on next app launch but stays closed
    // for the remainder of the current session.
    static let currentSessionID = UUID().uuidString

    @Published private(set) var trialStartDate: Date?

    private let trialDays = 7
    private let trialStartKey = "tutti.trial.startedAt"
    private let defaults: UserDefaults
    private let clock: () -> Date

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        self.trialStartDate = defaults.object(forKey: trialStartKey) as? Date
    }

    var isInTrial: Bool {
        guard let start = trialStartDate else { return false }
        // Use raw seconds, not Calendar.dateComponents([.day]) — the latter
        // is hybrid timezone/calendar-aware and can round 5*86400-second
        // gaps to 4 days depending on local hour-of-day boundaries.
        // Negative elapsed = clock skew (system time set backwards); refuse
        // to extend the window in that case.
        let elapsed = clock().timeIntervalSince(start)
        return elapsed >= 0 && elapsed < TimeInterval(trialDays) * 86_400
    }

    var daysRemaining: Int {
        guard let start = trialStartDate, isInTrial else { return 0 }
        let elapsed = clock().timeIntervalSince(start)
        let used = Int(elapsed / 86_400)
        return max(0, trialDays - used)
    }

    var hasUsedTrial: Bool { trialStartDate != nil }

    func startTrialIfFirstLaunch() {
        guard trialStartDate == nil else { return }
        let now = clock()
        defaults.set(now, forKey: trialStartKey)
        trialStartDate = now
    }
}

// Known limitation: isInTrial / daysRemaining are pure functions of the
// clock — they don't publish on natural expiry. A trial that lapses while
// the app is running won't flip UI to .trialExpired until something else
// triggers a re-render (popover reopen, license status change, etc.).
// Acceptable for v0.2.0 since the first popover open after midnight will
// catch it; revisit if user reports stale state.

#if DEBUG
enum TrialManagerTestHook {
    @MainActor
    static func setTrial(active: Bool) {
        if active {
            TrialManager.shared.trialStartDateForTesting = Date()
        } else {
            TrialManager.shared.trialStartDateForTesting = nil
        }
    }
}

extension TrialManager {
    fileprivate var trialStartDateForTesting: Date? {
        get { trialStartDate }
        set { trialStartDate = newValue }
    }
}
#endif
