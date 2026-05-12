import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let popover: TuttiPopover
    private let manager: AudioDeviceManager
    private var cancellable: AnyCancellable?

    init(manager: AudioDeviceManager, popover: TuttiPopover) {
        self.manager = manager
        self.popover = popover
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.target = self
        item.button?.action = #selector(handleClick(_:))
        updateIcon()
        cancellable = manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateIcon() }
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
        item.button?.image = TuttiPulseIcon.image(level: level)
    }
}
