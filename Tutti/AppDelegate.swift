import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let manager = AudioDeviceManager()
    private let profiles = ProfileStore()
    private let popover = TuttiPopover()
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    // Sparkle shows its update windows (progress, update alert, and the system
    // "you're up to date" NSAlert) wherever AppKit defaults them — the main
    // screen — ignoring which display the user dragged Settings to. Track each
    // foreign window the first time it becomes key and recenter it onto the
    // screen the user is actually looking at. Weak so closed windows drop out;
    // move-once so the user can freely drag it afterward.
    private let repositionedWindows = NSHashTable<NSWindow>.weakObjects()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 7-day Pro trial. Idempotent — only sets the start date the first
        // time, so re-launches don't reset it. Must run before any UI reads
        // LicenseManager.hasProAccess.
        TrialManager.shared.startTrialIfFirstLaunch()

        // Touch the Sparkle facade so its underlying SPUStandardUpdaterController
        // gets created + started at launch, not lazily when the user first
        // opens Settings. Notification category + UN delegate are registered
        // inside UpdateChecker.init.
        _ = UpdateChecker.shared

        let rootView = MenuBarView()
            .environmentObject(manager)
            .environmentObject(profiles)
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(foreignWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    /// Recenter Sparkle's (and any other foreign) windows onto the screen the
    /// user is looking at, so an update alert follows the Settings window
    /// across displays instead of always opening on the main screen.
    @objc private func foreignWindowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        // Our own windows place themselves.
        if window === settingsWindow || window === onboardingWindow { return }
        if window is TuttiPanel { return }
        if repositionedWindows.contains(window) { return }
        repositionedWindows.add(window)

        guard let screen = anchorScreen(), window.screen !== screen else { return }
        let frame = window.frame
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    /// The display the user is most likely looking at: where Settings sits if
    /// open, else under the cursor, else the main screen.
    private func anchorScreen() -> NSScreen? {
        if let screen = settingsWindow?.screen { return screen }
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return hit
        }
        return NSScreen.main ?? NSScreen.screens.first
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

    func applicationWillTerminate(_ notification: Notification) {
        manager.cleanup()
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
