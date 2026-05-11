import Cocoa
import ApplicationServices

// NX_KEYTYPE constants from <IOKit/hidsystem/ev_keymap.h>
private let NX_KEYTYPE_SOUND_UP: UInt32 = 0
private let NX_KEYTYPE_SOUND_DOWN: UInt32 = 1
private let NX_KEYTYPE_MUTE: UInt32 = 7

enum VolumeKeyAction {
    case up(fine: Bool)
    case down(fine: Bool)
    case mute
}

// Captures hardware volume keys via CGEventTap so they fire regardless of app focus.
// Requires Accessibility permission — granted in System Settings > Privacy & Security.
final class VolumeKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Read from event tap callback thread, written from main thread. Bool access is
    // atomic on Apple platforms, and worst case we miss exactly one keypress.
    var interceptEnabled: Bool = false

    private let onKey: (VolumeKeyAction) -> Void

    init(onKey: @escaping (VolumeKeyAction) -> Void) {
        self.onKey = onKey
    }

    @discardableResult
    func start(promptForPermission: Bool) -> Bool {
        guard eventTap == nil else { return true }

        let trusted = AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt": promptForPermission
        ] as CFDictionary)
        guard trusted else { return false }

        // NSEvent.EventType.systemDefined (= 14) covers media key aux events;
        // CGEventType doesn't expose it as a named case.
        let mask: CGEventMask = 1 << UInt64(NSEvent.EventType.systemDefined.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: selfPtr
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit { stop() }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard interceptEnabled else { return Unmanaged.passUnretained(event) }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt32((nsEvent.data1 & 0xFFFF0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard isKeyDown else { return Unmanaged.passUnretained(event) }

        let fine = nsEvent.modifierFlags.contains(.shift) && nsEvent.modifierFlags.contains(.option)

        let action: VolumeKeyAction
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:   action = .up(fine: fine)
        case NX_KEYTYPE_SOUND_DOWN: action = .down(fine: fine)
        case NX_KEYTYPE_MUTE:       action = .mute
        default: return Unmanaged.passUnretained(event)
        }

        onKey(action)
        return nil
    }
}

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<VolumeKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type, event)
}
