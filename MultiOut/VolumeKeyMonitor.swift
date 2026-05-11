import Cocoa
import ApplicationServices

// NX_KEYTYPE constants from <IOKit/hidsystem/ev_keymap.h>
private let NX_KEYTYPE_SOUND_UP: UInt32 = 0
private let NX_KEYTYPE_SOUND_DOWN: UInt32 = 1
private let NX_KEYTYPE_MUTE: UInt32 = 7

// Matches macOS native step: 1/16 normal, 1/64 with Shift+Option.
private let coarseStep: Float = 1.0 / 16
private let fineStep: Float = 1.0 / 64

enum VolumeKeyAction {
    case adjust(delta: Float)
    case mute
}

// Captures hardware volume keys via CGEventTap so they fire regardless of app focus.
// Requires Accessibility permission — granted in System Settings > Privacy & Security.
final class VolumeKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var interceptEnabled: Bool = false

    var isRunning: Bool { eventTap != nil }

    private let onKey: (VolumeKeyAction) -> Void

    init(onKey: @escaping (VolumeKeyAction) -> Void) {
        self.onKey = onKey
    }

    @discardableResult
    func start(promptForPermission: Bool) -> Bool {
        guard eventTap == nil else { return true }

        // Use AX only for its UI side-effect (prompting). Its return value can be
        // stale on unsigned binaries — tapCreate below is the authoritative check.
        if promptForPermission {
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
        }

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
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
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

        let step = (nsEvent.modifierFlags.contains(.shift) && nsEvent.modifierFlags.contains(.option))
                   ? fineStep : coarseStep

        let action: VolumeKeyAction
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:   action = .adjust(delta: step)
        case NX_KEYTYPE_SOUND_DOWN: action = .adjust(delta: -step)
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
