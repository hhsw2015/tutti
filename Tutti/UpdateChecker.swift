import Foundation
import SwiftUI
import Sparkle
import UserNotifications

private let githubRepo = "BarryBarrywu/tutti"
private let notificationCategoryID = "tutti.update.newVersion"
private let notificationActionInstall = "tutti.update.action.install"

/// Facade around Sparkle's `SPUStandardUpdaterController`. Keeps the same
/// public surface (`status`, `autoCheckEnabled`, `check()`, `currentVersion`,
/// `hasUpdate`) so `SettingsView` doesn't need to know Sparkle is underneath.
///
/// Background checks land via `SPUStandardUserDriverDelegate` gentle reminders
/// (we post a system notification instead of letting Sparkle pop a modal);
/// user-initiated checks fall through to Sparkle's standard UI as-is.
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case error(String)
    }

    static let shared = UpdateChecker()

    @Published private(set) var status: Status = .idle
    @Published var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: "autoCheckUpdates")
            updaterController.updater.automaticallyChecksForUpdates = autoCheckEnabled
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var hasUpdate: Bool {
        if case .updateAvailable = status { return true }
        return false
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    private override init() {
        let stored = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true
        self.autoCheckEnabled = stored
        super.init()
        // Touch the lazy controller so Sparkle starts polling per Info.plist
        // settings. Don't override automaticallyChecksForUpdates here — the
        // didSet on autoCheckEnabled has not been wired up yet for the
        // initial value, so push it explicitly once.
        updaterController.updater.automaticallyChecksForUpdates = stored
        registerNotificationCategories()
    }

    func check() async {
        status = .checking
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        let fallback = URL(string: "https://github.com/\(githubRepo)/releases/latest")!
        let url = item.releaseNotesURL ?? fallback
        Task { @MainActor in
            self.status = .updateAvailable(version: version, url: url)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.status = .upToDate
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            self.status = .error(error.localizedDescription)
        }
    }
}

// MARK: - SPUStandardUserDriverDelegate (gentle reminders)

extension UpdateChecker: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Tell Sparkle: hands off scheduled (background) updates — we'll surface
    /// them via a system notification rather than a modal. User-initiated
    /// checks are unaffected (Sparkle always handles those).
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        return false
    }

    /// Sparkle is about to surface an update.
    ///
    /// - `handleShowingUpdate == false`: scheduled/background check; we own
    ///   the surfacing → post a notification.
    /// - `handleShowingUpdate == true`: user-initiated check; Sparkle is
    ///   showing its standard modal, nothing for us to do.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { @MainActor in
            await self.sendUpdateNotification(version: version)
        }
    }

    /// User engaged with Sparkle's UI for this update → drop any pending
    /// notification so it doesn't double up.
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        let version = update.displayVersionString
        Task { @MainActor in
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: ["tutti.update.\(version)"]
            )
        }
    }
}

// MARK: - User notifications

extension UpdateChecker: UNUserNotificationCenterDelegate {
    fileprivate func registerNotificationCategories() {
        let install = UNNotificationAction(
            identifier: notificationActionInstall,
            title: String(localized: "立即安装"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: notificationCategoryID,
            actions: [install],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
    }

    fileprivate func sendUpdateNotification(version: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Tutti 有新版本可用")
        content.body = String(
            format: String(localized: "%@ 现已可下载"),
            version
        )
        content.sound = .default
        content.categoryIdentifier = notificationCategoryID
        let request = UNNotificationRequest(
            identifier: "tutti.update.\(version)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Both the install action and tapping the body should bring up
        // Sparkle's standard update alert (where the user can confirm).
        Task { @MainActor in
            self.updaterController.checkForUpdates(nil)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Surface the banner even when Tutti is the active app (otherwise
        // background-only apps get nothing).
        completionHandler([.banner, .sound])
    }
}
