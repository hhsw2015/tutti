import Foundation
import Security

protocol TrialStore {
    func load() -> Date?
    func save(_ date: Date)
}

@MainActor
final class TrialManager: ObservableObject {
    static let shared = TrialManager()

    // Fresh per process. Banner dismissals are scoped against this so the
    // trialExpired banner reappears on next app launch but stays closed
    // for the remainder of the current session.
    static let currentSessionID = UUID().uuidString

    @Published private(set) var trialStartDate: Date?

    private let trialDays = 7
    private let store: TrialStore
    private let clock: () -> Date

    init(store: TrialStore = KeychainTrialStore(), clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.trialStartDate = store.load()
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
        store.save(now)
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

/// Persists the trial start date in the Keychain so a clean reinstall or
/// `defaults delete` can't reset the 7-day window. Stored as a generic
/// password under account `tutti.trial` / service `trial_started_at`; the
/// date is the seconds-since-reference-date encoded as a UTF-8 string.
struct KeychainTrialStore: TrialStore {
    private let account = "tutti.trial"
    private let service = "trial_started_at"
    private let legacyDefaultsKey = "tutti.trial.startedAt"

    func load() -> Date? {
        if let date = readKeychain() { return date }
        // One-time migration from the pre-Keychain build: move an existing
        // trial start out of UserDefaults and drop the old copy so no
        // tamperable trace remains.
        guard let legacy = UserDefaults.standard.object(forKey: legacyDefaultsKey) as? Date else {
            return nil
        }
        writeKeychain(legacy)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return legacy
    }

    func save(_ date: Date) {
        writeKeychain(date)
    }

    private func readKeychain() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8),
              let interval = TimeInterval(str) else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    private func writeKeychain(_ date: Date) {
        let data = Data(String(date.timeIntervalSinceReferenceDate).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
