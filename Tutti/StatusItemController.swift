import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let popover: TuttiPopover
    private let manager: AudioDeviceManager
    private var cancellable: AnyCancellable?
    private var currentLevel: Int = -1

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
        guard level != currentLevel else { return }
        currentLevel = level
        item.button?.image = TuttiPulseIcon.image(level: level)
    }
}
