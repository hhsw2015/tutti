import XCTest
@testable import Tutti

@MainActor
final class LicenseAccessTests: XCTestCase {

    override func tearDown() async throws {
        // Reset shared singletons so test order doesn't leak state.
        LicenseManagerTestHook.setStatus(.inactive)
        TrialManagerTestHook.setTrial(active: false)
    }

    func test_hasProAccess_trueWhenLicenseActivated() {
        LicenseManagerTestHook.setStatus(.activated)
        TrialManagerTestHook.setTrial(active: false)
        XCTAssertTrue(LicenseManager.hasProAccess)
    }

    func test_hasProAccess_trueWhenInOfflineGrace() {
        LicenseManagerTestHook.setStatus(.offlineGrace(daysLeft: 5))
        TrialManagerTestHook.setTrial(active: false)
        XCTAssertTrue(LicenseManager.hasProAccess)
    }

    func test_hasProAccess_trueWhenInTrial() {
        LicenseManagerTestHook.setStatus(.inactive)
        TrialManagerTestHook.setTrial(active: true)
        XCTAssertTrue(LicenseManager.hasProAccess)
    }

    func test_hasProAccess_falseWhenInactiveAndTrialEnded() {
        LicenseManagerTestHook.setStatus(.inactive)
        TrialManagerTestHook.setTrial(active: false)
        XCTAssertFalse(LicenseManager.hasProAccess)
    }

    func test_hasProAccess_falseWhenExpiredAndNoTrial() {
        LicenseManagerTestHook.setStatus(.expired)
        TrialManagerTestHook.setTrial(active: false)
        XCTAssertFalse(LicenseManager.hasProAccess)
    }
}
