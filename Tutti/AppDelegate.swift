import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let manager = AudioDeviceManager()
    private let popover = TuttiPopover()
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = MenuBarView()
            .environmentObject(manager)
            .environment(\.openTuttiSettings, OpenTuttiSettingsAction { [weak self] in
                self?.openSettings()
            })
            .environment(\.tuttiPopover, popover)

        let host = NSHostingController(rootView: rootView)
        popover.contentViewController = host

        statusItem = StatusItemController(manager: manager, popover: popover)
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
        win.styleMask = [.titled, .closable]
        win.title = "Tutti 设置"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(NSSize(width: 480, height: 500))
        win.center()
        settingsWindow = win

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
