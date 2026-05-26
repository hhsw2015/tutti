import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let popover: TuttiPopover
    private let manager: AudioDeviceManager
    private var cancellable: AnyCancellable?
    private var scrollMonitor: Any?
    private var currentLevel: Int = -1
    private var currentMuted: Bool = false

    init(manager: AudioDeviceManager, popover: TuttiPopover) {
        self.manager = manager
        self.popover = popover
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.target = self
        item.button?.action = #selector(handleClick(_:))
        updateIcon()
        // objectWillChange fires before any @Published mutates; defer to the next
        // runloop tick so reads see the post-change state.
        cancellable = manager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
        installScrollMonitor()
    }

    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            // Consume scrolls that landed on either our status bar button or
            // the popover panel. Anything else (settings window, other apps'
            // surfaces, etc.) passes through untouched.
            let onButton = event.window === self.item.button?.window
            let onPopover = event.window is TuttiPanel
            guard onButton || onPopover else { return event }

            let raw = Float(event.scrollingDeltaY) * 0.002
            let delta = max(-0.02, min(0.02, raw))
            guard delta != 0 else { return nil }
            Task { @MainActor in
                self.manager.handleScrollVolumeAdjust(by: delta)
            }
            return nil
        }
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let button = item.button else { return }
        popover.toggle(from: button)
    }

    private func updateIcon() {
        let level: Int
        if manager.isMuted {
            level = 0
        } else {
            let v = manager.masterVolume
            if v <= 0 { level = 0 }
            else if v > 0.5 { level = 2 }
            else { level = 1 }
        }
        let muted = manager.isMuted
        guard level != currentLevel || muted != currentMuted else { return }
        currentLevel = level
        currentMuted = muted
        item.button?.image = TuttiPulseIcon.image(level: level, muted: muted)
    }
}
