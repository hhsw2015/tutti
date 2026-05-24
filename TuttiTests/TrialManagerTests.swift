import XCTest
@testable import Tutti

@MainActor
final class TrialManagerTests: XCTestCase {

    private let suiteName = "tutti.trial.tests"
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_startTrialIfFirstLaunch_setsStartDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = TrialManager(defaults: defaults, clock: { now })

        manager.startTrialIfFirstLaunch()

        XCTAssertEqual(manager.trialStartDate, now)
        XCTAssertTrue(manager.isInTrial)
    }

    func test_startTrialIfFirstLaunch_isIdempotent() {
        let firstCall = Date(timeIntervalSince1970: 1_700_000_000)
        let secondCall = Date(timeIntervalSince1970: 1_700_000_000 + 86_400)
        var currentClock = firstCall
        let manager = TrialManager(defaults: defaults, clock: { currentClock })

        manager.startTrialIfFirstLaunch()
        currentClock = secondCall
        manager.startTrialIfFirstLaunch()

        XCTAssertEqual(manager.trialStartDate, firstCall)
    }

    func test_daysRemaining_countsDown() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var currentClock = start
        let manager = TrialManager(defaults: defaults, clock: { currentClock })

        manager.startTrialIfFirstLaunch()
        XCTAssertEqual(manager.daysRemaining, 7)

        currentClock = start.addingTimeInterval(86_400 * 3)
        XCTAssertEqual(manager.daysRemaining, 4)

        currentClock = start.addingTimeInterval(86_400 * 6)
        XCTAssertEqual(manager.daysRemaining, 1)
    }

    func test_isInTrial_falseAfterExpiry() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var currentClock = start
        let manager = TrialManager(defaults: defaults, clock: { currentClock })

        manager.startTrialIfFirstLaunch()
        XCTAssertTrue(manager.isInTrial)

        currentClock = start.addingTimeInterval(86_400 * 7)
        XCTAssertFalse(manager.isInTrial)
        XCTAssertEqual(manager.daysRemaining, 0)
    }

    func test_clockSkew_clampsToZero() {
        let savedFuture = Date(timeIntervalSince1970: 1_700_000_000 + 86_400 * 10)
        defaults.set(savedFuture, forKey: "tutti.trial.startedAt")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = TrialManager(defaults: defaults, clock: { now })

        XCTAssertFalse(manager.isInTrial)
    }

    func test_persistence_acrossInstances() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = TrialManager(defaults: defaults, clock: { now })
        first.startTrialIfFirstLaunch()

        let second = TrialManager(defaults: defaults, clock: { now })
        XCTAssertEqual(second.trialStartDate, now)
        XCTAssertTrue(second.isInTrial)
    }

    func test_hasUsedTrial_reflectsStartState() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = TrialManager(defaults: defaults, clock: { now })

        XCTAssertFalse(manager.hasUsedTrial)
        manager.startTrialIfFirstLaunch()
        XCTAssertTrue(manager.hasUsedTrial)
    }

    /// Regression: seconds-precision floor, not Calendar.dateComponents.
    /// 4.5 days of elapsed time must read as "4 days used, 3 days remaining"
    /// regardless of the local timezone or hour-of-day boundary the original
    /// dateComponents-based implementation was sensitive to.
    func test_daysRemaining_isFlooredFromSeconds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var currentClock = start
        let manager = TrialManager(defaults: defaults, clock: { currentClock })

        manager.startTrialIfFirstLaunch()

        // 4.5 days = 4 full days used
        currentClock = start.addingTimeInterval(86_400 * 4 + 86_400 / 2)
        XCTAssertTrue(manager.isInTrial)
        XCTAssertEqual(manager.daysRemaining, 3)

        // Just shy of 7 days = still in trial, 0 days remaining
        currentClock = start.addingTimeInterval(86_400 * 7 - 1)
        XCTAssertTrue(manager.isInTrial)
        XCTAssertEqual(manager.daysRemaining, 1)

        // Exactly 7 days = expired
        currentClock = start.addingTimeInterval(86_400 * 7)
        XCTAssertFalse(manager.isInTrial)

        // 10 days = clearly expired (matches scenario-3 manual test setup)
        currentClock = start.addingTimeInterval(86_400 * 10)
        XCTAssertFalse(manager.isInTrial)
        XCTAssertTrue(manager.hasUsedTrial)
    }
}
