import AppKit

@MainActor
final class TuttiPopover: NSObject, NSWindowDelegate {

    enum Behavior {
        case transient
        case permanent
    }

    private var panel: TuttiPanel?
    var behavior: Behavior = .transient
    var contentViewController: NSViewController?

    var isVisible: Bool { panel?.isVisible == true }

    func updateContentSize(_ size: CGSize) {
        guard let panel else { return }
        var frame = panel.frame
        let newHeight = size.height
        let newWidth = size.width
        if abs(frame.height - newHeight) < 0.5 && abs(frame.width - newWidth) < 0.5 { return }
        let topY = frame.maxY
        frame.size = NSSize(width: newWidth, height: newHeight)
        frame.origin.y = topY - newHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    func toggle(from button: NSStatusBarButton) {
        if isVisible { close() } else { show(from: button) }
    }

    func show(from button: NSStatusBarButton) {
        guard let contentViewController else { return }
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = TuttiPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = contentViewController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.delegate = self
        panel.animationBehavior = .none

        var rect = panel.frame
        rect.size = NSSize(width: 320, height: 220)
        panel.setFrame(rect, display: false)

        position(panel: panel, below: button)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func position(panel: NSPanel, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.frame.size

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let spacing: CGFloat = 4

        let proposedX = buttonFrame.midX - size.width / 2
        let clampedX = max(visible.minX + 4, min(proposedX, visible.maxX - size.width - 4))
        let y = buttonFrame.minY - size.height - spacing

        panel.setFrameOrigin(NSPoint(x: clampedX, y: y))
    }

    private var isMouseInside: Bool {
        guard let panel else { return false }
        return NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard behavior == .transient else { return }
        guard !isMouseInside else { return }
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        behavior == .transient
    }
}

final class TuttiPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}
