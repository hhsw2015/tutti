import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let manager = AudioDeviceManager()
    private let popover = TuttiPopover()
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 7-day Pro trial. Idempotent — only sets the start date the first
        // time, so re-launches don't reset it. Must run before any UI reads
        // LicenseManager.hasProAccess.
        TrialManager.shared.startTrialIfFirstLaunch()

        let rootView = MenuBarView()
            .environmentObject(manager)
            .environment(\.openTuttiSettings, OpenTuttiSettingsAction { [weak self] in
                self?.openSettings()
            })
            .environment(\.tuttiPopover, popover)

        let host = NSHostingController(rootView: rootView)
        popover.contentViewController = host
        popover.onVisibilityChange = { [weak manager] visible in
            manager?.setPopoverVisible(visible)
        }

        statusItem = StatusItemController(manager: manager, popover: popover)
        showOnboardingIfNeeded()
    }

    func openSettings() {
        popover.behavior = .permanent

        if let win = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let view = TuttiSettingsView()
            .environmentObject(manager)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.title = String(localized: "Tutti 设置")
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(NSSize(width: 720, height: 600))
        win.center()
        win.isMovableByWindowBackground = true
        // Hide the standalone zoom and miniaturize buttons — Settings is a
        // fixed-size panel, only Close (red) needs to be visible.
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        settingsWindow = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutti.onboarding.completed") else { return }
        let view = OnboardingView {
            UserDefaults.standard.set(true, forKey: "tutti.onboarding.completed")
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        }
        .environmentObject(manager)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 620, height: 520))
        win.center()
        win.isMovableByWindowBackground = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        onboardingWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) == settingsWindow else { return }
        popover.behavior = .transient
        popover.close()
        settingsWindow = nil
    }
}

struct OpenTuttiSettingsAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct OpenTuttiSettingsKey: EnvironmentKey {
    static let defaultValue = OpenTuttiSettingsAction(action: {})
}

extension EnvironmentValues {
    var openTuttiSettings: OpenTuttiSettingsAction {
        get { self[OpenTuttiSettingsKey.self] }
        set { self[OpenTuttiSettingsKey.self] = newValue }
    }
}

private struct TuttiPopoverKey: EnvironmentKey {
    @MainActor static let defaultValue: TuttiPopover? = nil
}

extension EnvironmentValues {
    var tuttiPopover: TuttiPopover? {
        get { self[TuttiPopoverKey.self] }
        set { self[TuttiPopoverKey.self] = newValue }
    }
}
