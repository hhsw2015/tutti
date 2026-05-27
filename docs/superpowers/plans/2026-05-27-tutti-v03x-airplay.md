# Tutti v0.3.x AirPlay Shortcut Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.3.x of Tutti with a `AirPlayCapsule` in the popover that lists LAN-reachable AirPlay devices (HomePod, Apple TV, other Macs) and switches the system default output with one tap, plus an HAL-fallback that surfaces already-activated AirPlay devices alongside local outputs.

**Architecture:** Discover AirPlay devices via ObjC-runtime reflection of private API (`AVOutputDeviceDiscoverySession` or related), switch via the already-spike-verified `AVOutputContext.defaultSharedOutputContext.setOutputDevice(_:options:)`. Two completely decoupled units: `AirPlayBrowser` (discovery) and `AirPlaySwitcher` (action). UI layer (`AirPlayCapsule`) dedupes against `AudioDeviceManager.devices` so already-activated AirPlay shows in DevicesCapsule and not-yet-activated ones show in AirPlayCapsule.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, CoreAudio, AVFoundation private API (via `NSClassFromString` reflection), Foundation `NetService` (Path 3 fallback).

**Spec:** `docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md`

**Prerequisites:**
- macOS 13+ build environment, macOS 26+ for spike testing
- Xcode 15+ with Developer ID signing identity `Developer ID Application: BaoLin Wu (RFW398ARA9)`
- `xcodegen` + `notarytool` configured (keychain profile `tutti-notary`)
- Local TuttiTests target overlay via `project.tests.yml` (gitignored) — already exists for license tests
- At least 1 HomePod + 1 Apple TV (or equivalent) on the developer's LAN for spike validation
- macOS Control Center → Sound → AirPlay must work for at least one device (proves the underlying system flow is healthy)

---

## File Structure

**New files (committed)**:
- `scripts/airplay-spike.swift` — standalone reflection spike script. Kept in tree for re-spike on future macOS versions
- `Tutti/AirPlayDevice.swift` — data model: `AirPlayDevice` struct + `AirPlayDeviceType` enum. Pure value types, no API dependency
- `Tutti/AirPlaySwitcher.swift` — `enum AirPlaySwitcher` with one static method, reflection wrapper around `AVOutputContext.setOutputDevice`
- `Tutti/AirPlayBrowser.swift` — `@MainActor ObservableObject` discovery service. Implementation body depends on Phase 0 outcome

**Conditional on Phase 0 success only**:
- `Tutti/AirPlayBrowser.swift` — only written if at least one discovery path works
- `Tutti/AirPlaySwitcher.swift` — only written if Path 1/2/3/4 success
- AirPlayCapsule changes to MenuBarView — only if browser exists

**Modified files (always)**:
- `Tutti/AudioDeviceManager.swift:244` — remove the `if transport == kAudioDeviceTransportTypeAirPlay { continue }` guard. This is the HAL fallback that ships regardless of Phase 0 outcome.

**Modified files (conditional)**:
- `Tutti/MenuBarView.swift` — add AirPlayCapsule + AirPlayRow + insert in body
- `Tutti/AppDelegate.swift` — instantiate AirPlayBrowser, wire popover visibility callbacks
- `Tutti/Localizable.xcstrings` — 4 new keys × 9 languages
- `project.yml` — possibly add `_airplay._tcp` Bonjour declaration if Path 3 is chosen

**New files (local-only, gitignored under `TuttiTests/`)**:
- `TuttiTests/AirPlaySwitcherTests.swift`
- `TuttiTests/AirPlayBrowserTests.swift`
- `TuttiTests/AirPlayBrowserFailureTests.swift`

---

## Phase 0: Spike (CRITICAL GATE)

**Goal:** Find ONE discovery API path that satisfies all 5 validation criteria. Fail-fast on each path. Total time budget: 1 working day.

### Task 0.1: Set up airplay-spike.swift skeleton

**Files:**
- Create: `scripts/airplay-spike.swift` (committed)

- [ ] **Step 0.1.1: Create the spike script with shared utilities**

```bash
cd "/Volumes/990 EP/Dev/tutti"
mkdir -p scripts
```

Create `scripts/airplay-spike.swift`:

```swift
#!/usr/bin/env swift
//
// AirPlay discovery API spike — tries each candidate path and prints findings.
// Standalone Swift script; run with: swift scripts/airplay-spike.swift [path1|path2|path3|path4|all]
//
// Background: macOS doesn't expose a public API to enumerate LAN AirPlay
// devices (only the currently-routed one via Core Audio HAL). This script
// probes four ObjC-runtime + Bonjour candidates to find an enumeration
// method that survives notarization and works on macOS 26+.
//

import Foundation
import AVFoundation
import ObjectiveC.runtime

// MARK: - Reflection helpers

func classExists(_ name: String) -> NSObject.Type? {
    return NSClassFromString(name) as? NSObject.Type
}

func printClassMethods(_ cls: AnyClass) {
    // Instance methods
    var instCount: UInt32 = 0
    if let instMethods = class_copyMethodList(cls, &instCount) {
        for i in 0..<Int(instCount) {
            let sel = method_getName(instMethods[i])
            print("  - instance: \(sel)")
        }
        free(instMethods)
    }

    // Class methods (live on the metaclass)
    if let meta: AnyClass = object_getClass(cls) {
        var classCount: UInt32 = 0
        if let classMethods = class_copyMethodList(meta, &classCount) {
            for i in 0..<Int(classCount) {
                let sel = method_getName(classMethods[i])
                print("  + class: \(sel)")
            }
            free(classMethods)
        }
    }
}

// MARK: - Path runners (defined in subsequent tasks)

func runPath1() { print("\n=== Path 1: AVOutputDeviceDiscoverySession ===\n"); /* Task 0.2 fills in */ }
func runPath2() { print("\n=== Path 2: AVOutputContext class methods ===\n"); /* Task 0.3 fills in */ }
func runPath3() { print("\n=== Path 3: NetServiceBrowser + AVOutputDevice mapping ===\n"); /* Task 0.4 fills in */ }
func runPath4() { print("\n=== Path 4: MRMediaRemoteService ===\n"); /* Task 0.5 fills in */ }

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
let target = args.first ?? "all"

switch target {
case "path1": runPath1()
case "path2": runPath2()
case "path3": runPath3()
case "path4": runPath4()
case "all": runPath1(); runPath2(); runPath3(); runPath4()
default:
    print("Usage: swift scripts/airplay-spike.swift [path1|path2|path3|path4|all]")
    exit(1)
}
```

- [ ] **Step 0.1.2: Verify it runs**

```bash
cd "/Volumes/990 EP/Dev/tutti"
swift scripts/airplay-spike.swift all 2>&1 | head -10
```

Expected: 4 section headers print, nothing crashes.

- [ ] **Step 0.1.3: Commit the skeleton**

```bash
git add scripts/airplay-spike.swift
git commit -m "scaffold airplay discovery api spike"
```

### Task 0.2: Path 1 — AVOutputDeviceDiscoverySession

**Files:**
- Modify: `scripts/airplay-spike.swift` (replace the `runPath1` stub)

- [ ] **Step 0.2.1: Replace `runPath1()` with the reflection probe**

```swift
func runPath1() {
    print("\n=== Path 1: AVOutputDeviceDiscoverySession ===\n")
    guard let cls = classExists("AVOutputDeviceDiscoverySession") else {
        print("[Path 1] NSClassFromString returned nil — class doesn't exist on this macOS")
        return
    }
    print("[Path 1] Class found: \(cls)")
    print("[Path 1] Methods:")
    printClassMethods(cls)

    // Try common init patterns
    let initSelectors = [
        "init",
        "initWithDeviceType:",
        "initWithRequestedDeviceTypes:",
        "discoverySessionForRequestedDeviceTypes:",
    ]

    for selName in initSelectors {
        let sel = NSSelectorFromString(selName)
        if cls.responds(to: sel) {
            print("[Path 1] +[\(cls) \(selName)] responds")
        }
    }

    // Try instantiating with no args
    let session = cls.init()
    print("[Path 1] Default init result: \(session)")

    // Look for delegate-related selectors
    var instCount: UInt32 = 0
    if let methods = class_copyMethodList(cls, &instCount) {
        for i in 0..<Int(instCount) {
            let sel = method_getName(methods[i])
            let selStr = NSStringFromSelector(sel)
            if selStr.contains("delegate") || selStr.contains("start") || selStr.contains("device") {
                print("[Path 1] interesting instance selector: \(selStr)")
            }
        }
        free(methods)
    }
}
```

- [ ] **Step 0.2.2: Run Path 1**

```bash
cd "/Volumes/990 EP/Dev/tutti"
swift scripts/airplay-spike.swift path1
```

Expected outcomes:
- **Best case**: class found + has `setDelegate:`, `start`, `availableDevices` or similar selectors → continue to Step 0.2.3
- **Class found but only constructor methods**: probably useful but needs more reflection → continue
- **`NSClassFromString returned nil`**: Path 1 dead → skip to Task 0.3

- [ ] **Step 0.2.3: If Path 1 looks live, write a minimal end-to-end discovery test**

Only execute this step if Step 0.2.2 found the class with discovery-related selectors. Add to `runPath1()` after the introspection:

```swift
    // Continue Path 1 only if introspection found promising selectors.
    // The exact follow-up depends on what selectors exist; this is
    // a starter pattern using the most common iOS shape:
    //
    //   AVOutputDeviceDiscoverySession *session =
    //     [[cls alloc] initWithDeviceType:typeAirPlay];
    //   session.delegate = self;
    //   [session start];
    //   // delegate gets -outputDeviceDiscoverySession:didChangeAvailableOutputDevices:
    //
    // If the class uses a different shape (e.g., +sharedSession,
    // or completionHandler-based), adapt this step before committing
    // the result back to the spike script.

    // Pseudo-code reminder for the implementer:
    // 1. Find the init selector (likely +sessionWithDeviceTypes: or -initWithDeviceTypes:)
    // 2. Find the start selector (likely -start or -startDiscovery)
    // 3. Find the delegate protocol (likely "AVOutputDeviceDiscoverySessionDelegate")
    // 4. Find the "available devices" property/method
    // 5. Wait 2 seconds, dump the devices, exit
```

- [ ] **Step 0.2.4: Document outcome**

After running, add a comment block at the top of `scripts/airplay-spike.swift` recording what was found:

```swift
// Path 1 result (run on YYYY-MM-DD, macOS X.Y):
//   - class found: yes / no
//   - selectors found: <list relevant ones>
//   - device list returned: <count, types>
//   - meets 5-criteria validation: yes / no
```

If yes → Path 1 wins, skip Tasks 0.3 / 0.4 / 0.5 and go to Task 0.6.

### Task 0.3: Path 2 — AVOutputContext class methods sweep (run only if Path 1 failed)

**Files:**
- Modify: `scripts/airplay-spike.swift` (replace `runPath2` stub)

- [ ] **Step 0.3.1: Replace `runPath2()` with full class method enumeration**

```swift
func runPath2() {
    print("\n=== Path 2: AVOutputContext class methods sweep ===\n")
    guard let cls = classExists("AVOutputContext") else {
        print("[Path 2] AVOutputContext NSClassFromString returned nil — unexpected, was found in v0.3.0 spike")
        return
    }
    print("[Path 2] Class found: \(cls)")

    guard let meta: AnyClass = object_getClass(cls) else {
        print("[Path 2] No metaclass — abort")
        return
    }

    var classCount: UInt32 = 0
    guard let classMethods = class_copyMethodList(meta, &classCount) else {
        print("[Path 2] class_copyMethodList returned nil")
        return
    }
    defer { free(classMethods) }

    print("[Path 2] All \(classCount) class methods:")
    var interesting: [String] = []
    for i in 0..<Int(classCount) {
        let sel = method_getName(classMethods[i])
        let selStr = NSStringFromSelector(sel)
        print("  + \(selStr)")
        let lower = selStr.lowercased()
        let keywords = ["discover", "candidate", "available", "browse", "session", "all", "shared"]
        if keywords.contains(where: { lower.contains($0) }) {
            interesting.append(selStr)
        }
    }

    print("\n[Path 2] Interesting selectors (discovery-adjacent):")
    for sel in interesting { print("  ★ \(sel)") }

    // Try invoking each interesting class method with no args; check return type
    for selStr in interesting {
        let sel = NSSelectorFromString(selStr)
        guard cls.responds(to: sel) else { continue }
        // Only invoke methods with 0 args (no colon = no params)
        if !selStr.contains(":") {
            let result = cls.perform(sel)?.takeUnretainedValue()
            print("[Path 2] +[\(cls) \(selStr)] → \(String(describing: result))")
            if let array = result as? NSArray {
                print("    array of \(array.count) elements")
                for item in array {
                    print("    - \(type(of: item)): \(item)")
                }
            }
        }
    }
}
```

- [ ] **Step 0.3.2: Run Path 2**

```bash
cd "/Volumes/990 EP/Dev/tutti"
swift scripts/airplay-spike.swift path2
```

Expected outcomes:
- **Best case**: An `+allKnownDevices` / `+availableOutputContexts` / similar method returns a non-empty `NSArray` of `AVOutputDevice`-like objects → Path 2 wins
- **All methods return nil or unusable types**: Path 2 dead → Task 0.4

- [ ] **Step 0.3.3: Document outcome at top of spike script (same format as Step 0.2.4)**

If Path 2 wins → skip Tasks 0.4 / 0.5, go to Task 0.6.

### Task 0.4: Path 3 — NetServiceBrowser + AVOutputDevice mapping (run only if Path 2 failed)

**Files:**
- Modify: `scripts/airplay-spike.swift` (replace `runPath3` stub)

- [ ] **Step 0.4.1: Replace `runPath3()` with two-phase test**

```swift
func runPath3() {
    print("\n=== Path 3: NetServiceBrowser + AVOutputDevice mapping ===\n")

    // Phase 3a: Can we discover AirPlay endpoints via mDNS?
    let browser = NetServiceBrowser()
    let delegate = NetServiceBrowserDelegateImpl()
    browser.delegate = delegate
    browser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")

    // Run RunLoop for 3 seconds to give Bonjour time to discover
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }

    browser.stop()

    print("[Path 3a] Discovered \(delegate.services.count) _airplay._tcp services:")
    for svc in delegate.services {
        print("  - \(svc.name) @ \(svc.hostName ?? "?"):\(svc.port)")
    }

    if delegate.services.isEmpty {
        print("[Path 3a] No services found — Bonjour either restricted or no AirPlay endpoints on LAN")
        return
    }

    // Phase 3b: Try to construct AVOutputDevice for the first endpoint
    guard let avOutputDeviceCls = classExists("AVOutputDevice") else {
        print("[Path 3b] AVOutputDevice class not found")
        return
    }

    print("[Path 3b] AVOutputDevice class found, inspecting class methods:")
    guard let meta: AnyClass = object_getClass(avOutputDeviceCls) else { return }
    var count: UInt32 = 0
    if let methods = class_copyMethodList(meta, &count) {
        for i in 0..<Int(count) {
            print("  + \(NSStringFromSelector(method_getName(methods[i])))")
        }
        free(methods)
    }

    // Common patterns: +deviceWithUID:, +deviceWithName:, +deviceWithHost:
    let constructorSelectors = [
        "deviceWithUID:",
        "deviceWithName:",
        "deviceWithHost:",
        "deviceWithIdentifier:",
        "outputDeviceWithUID:",
    ]
    for selName in constructorSelectors {
        let sel = NSSelectorFromString(selName)
        if avOutputDeviceCls.responds(to: sel) {
            print("[Path 3b] +[AVOutputDevice \(selName)] EXISTS — try invoking with hostname")
            if let firstSvc = delegate.services.first, let host = firstSvc.hostName {
                let device = avOutputDeviceCls.perform(sel, with: host)?.takeUnretainedValue()
                print("[Path 3b] result: \(String(describing: device))")
            }
        }
    }
}

class NetServiceBrowserDelegateImpl: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var services: [NetService] = []

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 2)
        services.append(service)
    }
}
```

- [ ] **Step 0.4.2: Run Path 3**

```bash
cd "/Volumes/990 EP/Dev/tutti"
swift scripts/airplay-spike.swift path3
```

Expected outcomes:
- **Best case**: 2+ services discovered AND a `+deviceWithUID:`-style constructor returns a non-nil AVOutputDevice that survives passing to `setOutputDevice` → Path 3 wins
- **Bonjour finds services but no constructor matches**: dead, no way to map endpoint → AVOutputDevice → Task 0.5
- **Bonjour finds nothing**: LAN issue or APIs differ → Task 0.5 (and verify Bonjour works in general)

- [ ] **Step 0.4.3: Document outcome**

If Path 3 wins → skip Task 0.5, go to Task 0.6.

### Task 0.5: Path 4 — MRMediaRemoteService (run only if Path 3 failed)

**Files:**
- Modify: `scripts/airplay-spike.swift` (replace `runPath4` stub)

- [ ] **Step 0.5.1: Replace `runPath4()` with framework probe**

```swift
func runPath4() {
    print("\n=== Path 4: MRMediaRemoteService ===\n")

    // The framework is at /System/Library/PrivateFrameworks/MediaRemote.framework
    // Symbols include MRMediaRemoteGetNowPlayingApplicationDisplayID etc.
    // For AirPlay device enumeration, the relevant class is most likely
    // MRDestinationGroup or MRDevice — both private.

    let candidateClasses = [
        "MRMediaRemoteService",
        "MRDestinationGroup",
        "MRDevice",
        "MRAVRoutingController",
        "MRAVOutputDevice",
    ]

    for name in candidateClasses {
        if let cls = classExists(name) {
            print("[Path 4] \(name) FOUND")
            printClassMethods(cls)
            print("")
        } else {
            print("[Path 4] \(name) NOT FOUND")
        }
    }
}
```

- [ ] **Step 0.5.2: Run Path 4**

```bash
cd "/Volumes/990 EP/Dev/tutti"
swift scripts/airplay-spike.swift path4
```

Expected outcomes:
- **Best case**: One of the candidate classes exists AND has device enumeration selectors → drill in further (this likely needs another 2-4 hours of manual reverse engineering — escalate to the user before continuing)
- **All classes missing**: Path 4 dead → trigger spike-fail tree (Task 0.7)

- [ ] **Step 0.5.3: Document outcome**

If Path 4 looks promising → escalate to user with findings; do not auto-commit to it.
If Path 4 dead → go to Task 0.7 (spike fail).

### Task 0.6: Spike Success — Document the winning path

**Files:**
- Modify: `scripts/airplay-spike.swift` (add a top-of-file comment block summarizing the winner)
- Modify: `docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md` (add a "Spike Result" section)

- [ ] **Step 0.6.1: Add a "Spike Result" section to the spec**

Edit `docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md`. Insert directly after the existing "已知 Spike 结论" section:

```markdown
## Spike Result (Phase 0 outcome, YYYY-MM-DD)

**Winning path:** Path N — <name>

**Discovery API surface used:**
- Class: `<NSClassFromString name>`
- Init: `<selector>`
- Start: `<selector>`
- Devices accessor: `<selector or property>`
- Delegate protocol (if any): `<protocol name and callback selectors>`

**Validation against 5 criteria:**
1. ✅ Enumerated devices: <list specific devices found, e.g., "Barry's HomePod 2, Barry's HomePod 3, Barry's TV">
2. ✅ Device object accepted by `AVOutputContext.setOutputDevice(_:options:)`: <yes/no, with switch test result>
3. ✅ System default output changed visibly in Sound menu after switch: <yes/no>
4. ✅ Device not pre-activated in Control Center was still discoverable: <yes/no>
5. ✅ Hardened Runtime + notarized .app accepts the reflection call: <pending Phase A.6 verification>

**Notable selectors collected from introspection** (for AirPlayBrowser implementation):
- <copy the relevant ones from spike output>

**Rejected paths:**
- Path 1/2/3/4 (whichever weren't used): <brief reason>
```

Fill in the actuals from the spike output. Commit it.

- [ ] **Step 0.6.2: Commit the spike findings**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add scripts/airplay-spike.swift docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md
git commit -m "record airplay discovery spike findings"
```

After this, continue to Task A.1 with the winning path's selectors known.

### Task 0.7: Spike Fail — Document and downscope (only if all 4 paths failed)

**Files:**
- Modify: `docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md` (record spike failure)

- [ ] **Step 0.7.1: Record the failure**

Edit `docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md` with a "Spike Result" section reporting all 4 paths failed and what was observed for each.

- [ ] **Step 0.7.2: Downscope this plan**

Skip Tasks A.1, A.2, A.3, A.4, C.1, C.2, D.1, E.1.
Execute only Tasks B.1, F.1 (modified), F.2, F.3.

The shipped version becomes a minor release with only the HAL filter removal — already-activated AirPlay surfaces in `DevicesCapsule` alongside local devices. No new capsule, no new wiring.

- [ ] **Step 0.7.3: Commit the abort decision**

```bash
git add docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md
git commit -m "abort airplay browser approach, downscope v0.3.x to HAL-only"
```

Then jump to Phase B.

---

## Phase A: AirPlay Primitives

**Goal:** Build the discovery + switching primitives. Only execute if Task 0.6 succeeded.

### Task A.1: AirPlayDevice + AirPlayDeviceType data model

**Files:**
- Create: `Tutti/AirPlayDevice.swift` (committed)

- [ ] **Step A.1.1: Create the data model file**

```swift
import Foundation

struct AirPlayDevice: Identifiable, Equatable, Hashable {
    /// Stable identifier from the discovery API.
    /// For Path 1 (AVOutputDeviceDiscoverySession) this is typically AVOutputDevice.deviceID.
    /// For Path 3 (NetServiceBrowser) this is typically the service hostname.
    let id: String
    /// User-visible name, e.g., "Barry's HomePod 2".
    let name: String
    /// True when this device is the current default output route.
    let isActive: Bool
    /// Used to pick the SF Symbol for the row icon.
    let deviceType: AirPlayDeviceType

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AirPlayDevice, rhs: AirPlayDevice) -> Bool { lhs.id == rhs.id }
}

enum AirPlayDeviceType {
    case homepod
    case appleTV
    case mac
    case speaker
    case unknown

    /// Heuristic mapper from a discovery-API device-type hint string to our enum.
    /// The exact strings depend on the winning Phase 0 path:
    /// - Path 1 reports `AVOutputDevice.deviceType` strings like "AirPlayDeviceTypeHomePod"
    /// - Path 3 derives type from mDNS TXT record "model" key (e.g., "AppleTV5,3")
    static func from(rawType: String?) -> AirPlayDeviceType {
        guard let raw = rawType?.lowercased() else { return .unknown }
        if raw.contains("homepod") { return .homepod }
        if raw.contains("appletv") || raw.contains("apple tv") { return .appleTV }
        if raw.contains("mac") { return .mac }
        if raw.contains("speaker") || raw.contains("audio") { return .speaker }
        return .unknown
    }

    /// SF Symbol used by AirPlayRow for the leading icon.
    var symbolName: String {
        switch self {
        case .homepod: return "homepod.fill"
        case .appleTV: return "appletv.fill"
        case .mac: return "desktopcomputer"
        case .speaker: return "hifispeaker.fill"
        case .unknown: return "airplayaudio"
        }
    }
}
```

- [ ] **Step A.1.2: Build to confirm**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodegen generate --spec project.tests.yml
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step A.1.3: Commit**

```bash
git add Tutti/AirPlayDevice.swift
git commit -m "add airplay device data model"
```

### Task A.2: AirPlaySwitcher

**Files:**
- Create: `Tutti/AirPlaySwitcher.swift` (committed)
- Create: `TuttiTests/AirPlaySwitcherTests.swift` (local-only, gitignored)

- [ ] **Step A.2.1: Write failing test**

Create `TuttiTests/AirPlaySwitcherTests.swift`:

```swift
import XCTest
@testable import Tutti

final class AirPlaySwitcherTests: XCTestCase {
    /// Smoke test: the public API exists, accepts an AirPlayDevice, and
    /// returns a Bool without crashing even when no AirPlay device is present.
    func testSwitchToReturnsBoolForUnknownDevice() {
        let device = AirPlayDevice(
            id: "fake-uid-00000000",
            name: "Fake Device",
            isActive: false,
            deviceType: .unknown
        )
        let result = AirPlaySwitcher.switchTo(device)
        // We don't assert true/false — depends on whether reflection
        // succeeded in the test process. We only assert "doesn't crash".
        XCTAssertNotNil(result as Any?)
    }
}
```

- [ ] **Step A.2.2: Run test to verify it fails**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/AirPlaySwitcherTests 2>&1 | tail -10
```

Expected: compile failure (`AirPlaySwitcher` not defined).

- [ ] **Step A.2.3: Implement AirPlaySwitcher**

Create `Tutti/AirPlaySwitcher.swift`:

```swift
import Foundation
import os.log

/// Synchronously switches the macOS default audio output to the given
/// AirPlay device by invoking the private
/// `AVOutputContext.defaultSharedOutputContext.setOutputDevice(_:options:)`
/// selector via ObjC runtime reflection.
///
/// Returns true on success, false on any failure (class missing, selector
/// missing, setOutputDevice returned an error, device object construction
/// failed). All failures are silent + logged to os_log.
enum AirPlaySwitcher {
    private static let log = OSLog(subsystem: "com.recents.tutti", category: "airplay")

    static func switchTo(_ device: AirPlayDevice) -> Bool {
        // 1. Resolve AVOutputContext.defaultSharedOutputContext
        guard let ctxClass = NSClassFromString("AVOutputContext") as? NSObject.Type else {
            os_log("AVOutputContext class missing", log: log, type: .error)
            return false
        }
        let defaultSharedSel = NSSelectorFromString("defaultSharedOutputContext")
        guard ctxClass.responds(to: defaultSharedSel) else {
            os_log("defaultSharedOutputContext selector missing", log: log, type: .error)
            return false
        }
        guard let ctx = ctxClass.perform(defaultSharedSel)?.takeUnretainedValue() as? NSObject else {
            os_log("defaultSharedOutputContext returned nil", log: log, type: .error)
            return false
        }

        // 2. Construct an AVOutputDevice for the target.
        //    The exact constructor depends on Phase 0 outcome:
        //    - Path 1/2 (AVOutputDeviceDiscoverySession): typically the device
        //      object is already an AVOutputDevice — passed through unchanged.
        //      In this case, AirPlayBrowser stores the AVOutputDevice
        //      reference in a side-table keyed by AirPlayDevice.id.
        //    - Path 3 (NetServiceBrowser): construct via +[AVOutputDevice
        //      deviceWithUID:] or whichever factory was confirmed.
        //
        //    For now, look up the device object from AirPlayBrowser.
        guard let targetDevice = AirPlayBrowser.shared.rawDevice(forID: device.id) else {
            os_log("No raw AVOutputDevice for id %{public}@", log: log, type: .error, device.id)
            return false
        }

        // 3. Invoke setOutputDevice:options:
        let setOutputSel = NSSelectorFromString("setOutputDevice:options:")
        guard ctx.responds(to: setOutputSel) else {
            os_log("setOutputDevice:options: selector missing", log: log, type: .error)
            return false
        }
        // perform(_:with:with:) is the 2-arg variant
        let _ = ctx.perform(setOutputSel, with: targetDevice, with: nil)
        return true
    }
}
```

**Note**: This references `AirPlayBrowser.shared.rawDevice(forID:)` which is defined in Task A.3. If you implement A.2 before A.3, this won't compile yet — that's fine, we'll iterate. Either:
- Stub `AirPlayBrowser.shared.rawDevice(forID:)` first, OR
- Implement A.3 first and reorder.

The plan is written so the implementer can choose either ordering. For TDD purposes, recommend stubbing here and filling in A.3.

- [ ] **Step A.2.4: Add a stub for AirPlayBrowser.shared.rawDevice — temporary, fully replaced in A.3**

If you took the order A.2 → A.3, create a minimal scaffold so A.2's test compiles. Add to `Tutti/AirPlaySwitcher.swift` at the bottom:

```swift
// Temporary scaffold so AirPlaySwitcher compiles before AirPlayBrowser exists.
// Replaced by the real AirPlayBrowser in Task A.3.
final class AirPlayBrowser {
    static let shared = AirPlayBrowser()
    func rawDevice(forID id: String) -> NSObject? { nil }
}
```

This stub will be replaced in Task A.3 step A.3.3 (delete this scaffold, create real `Tutti/AirPlayBrowser.swift`).

- [ ] **Step A.2.5: Run test to verify it passes**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/AirPlaySwitcherTests 2>&1 | tail -10
```

Expected: 1 test passes. Result is `true` if reflection finds AVOutputContext, `false` otherwise. Either way no crash.

- [ ] **Step A.2.6: Commit**

```bash
git add Tutti/AirPlaySwitcher.swift
git status  # confirm test file NOT staged
git commit -m "add airplay switcher with avoutputcontext reflection"
```

### Task A.3: AirPlayBrowser

**Files:**
- Create: `Tutti/AirPlayBrowser.swift` (committed)
- Create: `TuttiTests/AirPlayBrowserTests.swift` (local-only)
- Create: `TuttiTests/AirPlayBrowserFailureTests.swift` (local-only)

- [ ] **Step A.3.1: Write failing test for discovery**

Create `TuttiTests/AirPlayBrowserTests.swift`:

```swift
import XCTest
@testable import Tutti

@MainActor
final class AirPlayBrowserTests: XCTestCase {
    func testInitialDevicesIsEmpty() {
        let browser = AirPlayBrowser()
        XCTAssertEqual(browser.devices, [])
    }

    func testStartContinuousScanIsNonBlocking() async {
        let browser = AirPlayBrowser()
        let start = Date()
        browser.startContinuousScan()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1, "startContinuousScan should return immediately")
        browser.stopContinuousScan()
    }

    func testStopContinuousScanIsIdempotent() {
        let browser = AirPlayBrowser()
        browser.stopContinuousScan()  // before start
        browser.startContinuousScan()
        browser.stopContinuousScan()
        browser.stopContinuousScan()  // double-stop
        // No crash = pass
    }
}
```

- [ ] **Step A.3.2: Write failure test**

Create `TuttiTests/AirPlayBrowserFailureTests.swift`:

```swift
import XCTest
@testable import Tutti

@MainActor
final class AirPlayBrowserFailureTests: XCTestCase {
    /// Smoke: even on a machine with zero AirPlay devices and no reflection
    /// classes present, the browser must not crash and must report devices = [].
    func testBrowserSurvivesNoAvailableAPIs() async {
        let browser = AirPlayBrowser()
        browser.startContinuousScan()
        // Wait up to 2s for any discovery
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        browser.stopContinuousScan()
        // devices may be 0 or N — we only assert non-crash.
        XCTAssertNotNil(browser.devices as Any?)
    }
}
```

- [ ] **Step A.3.3: Run tests to verify they fail**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/AirPlayBrowserTests \
  -only-testing:TuttiTests/AirPlayBrowserFailureTests 2>&1 | tail -10
```

Expected: compile failure — `AirPlayBrowser` may already exist as the A.2 scaffold but lacks the methods used here.

- [ ] **Step A.3.4: Implement AirPlayBrowser**

First, delete the scaffold added in A.2.4 from `Tutti/AirPlaySwitcher.swift` (the bottom-of-file `final class AirPlayBrowser` block).

Then create `Tutti/AirPlayBrowser.swift`:

```swift
import Foundation
import Combine
import os.log

@MainActor
final class AirPlayBrowser: ObservableObject {
    static let shared = AirPlayBrowser()

    @Published private(set) var devices: [AirPlayDevice] = []

    private let log = OSLog(subsystem: "com.recents.tutti", category: "airplay")

    /// Discovery API session/object retained for the scan lifetime.
    /// Exact type depends on the winning Phase 0 path. Use NSObject as
    /// the storage type since we hold via ObjC reflection.
    private var session: NSObject?

    /// Side-table mapping AirPlayDevice.id -> the underlying AVOutputDevice
    /// (or equivalent) needed by AirPlaySwitcher. Populated when discovery
    /// fires; cleared on stopContinuousScan.
    private var rawDevices: [String: NSObject] = [:]

    /// Returns the underlying device object for the given ID, used by
    /// AirPlaySwitcher.switchTo to invoke setOutputDevice.
    func rawDevice(forID id: String) -> NSObject? {
        rawDevices[id]
    }

    func startContinuousScan() {
        // PHASE A.3.4 IMPLEMENTATION NOTE:
        //
        // The body of this function depends on the Phase 0 winning path.
        // Choose ONE of the patterns below based on the spike result
        // recorded in scripts/airplay-spike.swift and the spec.
        //
        // -------- Pattern P1 (AVOutputDeviceDiscoverySession) --------
        // Use this if Phase 0 Task 0.2 succeeded.
        //
        //   guard let cls = NSClassFromString("AVOutputDeviceDiscoverySession") as? NSObject.Type else {
        //     os_log("AVOutputDeviceDiscoverySession missing", log: log, type: .error)
        //     return
        //   }
        //   // The constructor selector depends on what Phase 0 found.
        //   // For example, if Phase 0 found +discoverySessionForRequestedDeviceTypes:
        //   let sel = NSSelectorFromString("discoverySessionForRequestedDeviceTypes:")
        //   guard cls.responds(to: sel) else { return }
        //   // ... etc. Set delegate, call -startDiscovery, await callback,
        //   //     populate self.devices + self.rawDevices.
        //
        // -------- Pattern P2 (AVOutputContext class method) --------
        // Use this if Phase 0 Task 0.3 succeeded.
        //
        //   guard let ctxCls = NSClassFromString("AVOutputContext") as? NSObject.Type else { return }
        //   let sel = NSSelectorFromString("<the-winning-class-method-from-spike>")
        //   guard ctxCls.responds(to: sel) else { return }
        //   if let array = ctxCls.perform(sel)?.takeUnretainedValue() as? [NSObject] {
        //     // Map each NSObject to AirPlayDevice + populate rawDevices dict.
        //   }
        //
        // -------- Pattern P3 (NetServiceBrowser) --------
        // Use this if Phase 0 Task 0.4 succeeded.
        //
        //   let browser = NetServiceBrowser()
        //   browser.delegate = self  // implement NetServiceBrowserDelegate
        //   browser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
        //   self.session = browser
        //   // In netServiceBrowser(_:didFind:moreComing:), resolve each
        //   // service, then call +[AVOutputDevice deviceWithUID:] with the
        //   // resolved hostname. Populate rawDevices.
        //
        // ---------------------------------------------------------------
        //
        // For the initial implementation, use the pattern matching Phase 0
        // Task 0.6 spec result. The variables in PLACEHOLDER positions
        // must match the selectors recorded in the spec.
        //
        // SAFE DEFAULT: if you haven't yet wired the discovery, leaving
        // this function as a no-op is acceptable. devices stays [].
        //   The capsule will simply not appear in the popover.
        //   Phase A.6 verification will catch this as a regression.

        os_log("startContinuousScan called", log: log, type: .info)
    }

    func stopContinuousScan() {
        if let session = session {
            // Pattern P1/P2: call -stopDiscovery via reflection if applicable
            // Pattern P3: cast to NetServiceBrowser and call .stop()
            if let nsBrowser = session as? NetServiceBrowser {
                nsBrowser.stop()
            } else {
                let stopSel = NSSelectorFromString("stopDiscovery")
                if session.responds(to: stopSel) {
                    session.perform(stopSel)
                }
            }
        }
        session = nil
        // Keep devices/rawDevices populated so the UI doesn't flicker
        // when the popover closes — they'll be refreshed on next open.
        os_log("stopContinuousScan called", log: log, type: .info)
    }

    func refresh() async {
        // Trigger a one-shot rescan, used by AppDelegate.popover visibility
        // callback. For pattern P3 (Bonjour) this means start, wait 2s, stop.
        // For P1/P2 it may not be needed (continuous discovery delivers
        // updates via delegate callbacks).
        stopContinuousScan()
        startContinuousScan()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
}
```

**Important**: The implementer must fill in the chosen `startContinuousScan()` pattern based on the Phase 0 winning path. The plan deliberately leaves this body abstract because the spike result determines the concrete code. Do NOT ship the no-op version — Phase A.6 verification will reject it.

- [ ] **Step A.3.5: Run tests to verify they pass**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/AirPlayBrowserTests \
  -only-testing:TuttiTests/AirPlayBrowserFailureTests 2>&1 | tail -10
```

Expected: all 4 tests pass (3 in `AirPlayBrowserTests` + 1 in `AirPlayBrowserFailureTests`).

- [ ] **Step A.3.6: Commit**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add Tutti/AirPlayBrowser.swift Tutti/AirPlaySwitcher.swift
git status  # only the two production files
git commit -m "add airplay browser with discovery api reflection"
```

(The AirPlaySwitcher.swift change is the deletion of the scaffold.)

### Task A.4: End-to-end manual verification (no automated test possible — relies on real LAN devices)

**Files:** (no source changes)

- [ ] **Step A.4.1: Write a tiny manual exerciser**

In `scripts/airplay-spike.swift`, append a `runEndToEnd` function:

```swift
func runEndToEnd() {
    print("\n=== End-to-end: AirPlayBrowser + AirPlaySwitcher ===\n")
    // This requires the production AirPlayBrowser to be linkable from
    // the spike script. Since the script is standalone Swift, simulate
    // the production code's reflection sequence here directly using the
    // same selectors that Tutti/AirPlayBrowser.swift uses.
    //
    // After Phase 0 records the winning path, copy the discovery
    // sequence here verbatim for a one-shot validation.
}
```

After Tasks A.1-A.3 are done, copy the production sequence into this function so the spike script can validate end-to-end without needing a full Tutti.app launch.

- [ ] **Step A.4.2: Run end-to-end**

```bash
swift scripts/airplay-spike.swift all
```

Verify: in the End-to-end section, at least one device is discovered AND a switch attempt fires `setOutputDevice` (you'll hear/see the system output change).

### Task A.5: Notarize early — catch reflection signing issues before Phase B-F

**Files:** (no source changes)

- [ ] **Step A.5.1: Build, sign, and notarize a spike build now**

```bash
cd "/Volumes/990 EP/Dev/tutti"
rm -rf build/early-notarize

BUILD_DIR="build/early-notarize"
ARCHIVE="$BUILD_DIR/Tutti.xcarchive"
EXPORT="$BUILD_DIR/export"
APP="$EXPORT/Tutti.app"
SIGN_IDENTITY="Developer ID Application: BaoLin Wu (RFW398ARA9)"

mkdir -p "$BUILD_DIR"

xcodebuild -project Tutti.xcodeproj -scheme Tutti -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" archive

cat > "$BUILD_DIR/ExportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>RFW398ARA9</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

ZIP="$BUILD_DIR/Tutti-early.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "tutti-notary" --wait
xcrun stapler staple "$APP"
spctl --assess --verbose "$APP"
```

Expected: `status: Accepted` from notarytool, `accepted, source=Notarized Developer ID` from spctl.

- [ ] **Step A.5.2: If notarize fails on the reflection code, STOP**

If notarize rejects, read the log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "tutti-notary"
```

Common failure: certain private framework references are flagged. If this happens, the chosen Path may not be ship-able. Escalate to user before proceeding.

### Task A.6: Production functional smoke test (in a notarized .app)

- [ ] **Step A.6.1: Install the early-notarize build and verify discovery**

```bash
rm -rf /tmp/Tutti.app
cp -R build/early-notarize/export/Tutti.app /tmp/Tutti.app
xattr -dr com.apple.quarantine /tmp/Tutti.app
killall Tutti 2>/dev/null || true
open /tmp/Tutti.app
```

Open Console.app, filter `subsystem:com.recents.tutti category:airplay`. Open the Tutti popover. Verify in the console log:
- `startContinuousScan called`
- One or more lines indicating device discovery (depends on the implementation)
- Eventually `browser.devices.count > 0` if any AirPlay devices are reachable

If `devices` stays empty despite reachable AirPlay devices on the LAN, the implementation in Task A.3 is incomplete and must be fixed before continuing.

---

## Phase B: HAL Filter Removal (ALWAYS — runs even if Phase 0 failed)

### Task B.1: Remove the AirPlay continue at AudioDeviceManager.swift:244

**Files:**
- Modify: `Tutti/AudioDeviceManager.swift` (single line removal)

- [ ] **Step B.1.1: Read the current line**

```bash
cd "/Volumes/990 EP/Dev/tutti"
sed -n '240,248p' Tutti/AudioDeviceManager.swift
```

Expected output:
```swift
            let transport = readTransportType(id)
            // AirPlay devices can't be aggregated — Audio MIDI Setup hides them too.
            if transport == kAudioDeviceTransportTypeAirPlay { continue }
            newDevices.append(AudioDevice(id: id, name: name, uid: uid,
                                          canSetVolume: checkSettable(id),
                                          transportType: transport))
```

- [ ] **Step B.1.2: Edit the file — delete the continue and update the comment**

Using the Edit tool, replace:

```swift
            let transport = readTransportType(id)
            // AirPlay devices can't be aggregated — Audio MIDI Setup hides them too.
            if transport == kAudioDeviceTransportTypeAirPlay { continue }
            newDevices.append(AudioDevice(id: id, name: name, uid: uid,
                                          canSetVolume: checkSettable(id),
                                          transportType: transport))
```

with:

```swift
            let transport = readTransportType(id)
            // AirPlay devices are surfaced through HAL only when they're the
            // current active route. AirPlayBrowser handles enumerating
            // not-yet-active devices in a separate capsule; HAL output here
            // is the fallback for already-active ones (visible alongside
            // local outputs in DevicesCapsule).
            newDevices.append(AudioDevice(id: id, name: name, uid: uid,
                                          canSetVolume: checkSettable(id),
                                          transportType: transport))
```

- [ ] **Step B.1.3: Build to verify nothing else broke**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step B.1.4: Verify HAL fallback works manually**

```bash
killall Tutti 2>/dev/null || true
xcodebuild -project Tutti.xcodeproj -scheme Tutti -configuration Debug \
  -derivedDataPath build/halcheck build 2>&1 | tail -3
open build/halcheck/Build/Products/Debug/Tutti.app
```

In macOS Control Center → Sound, switch to a HomePod (this activates the AirPlay route in HAL). Then open Tutti popover. Expected: the HomePod now appears in `DevicesCapsule` alongside local outputs, with an `airplayaudio` SF symbol (since `AudioDevice.symbolName` already handles `kAudioDeviceTransportTypeAirPlay`).

Switch back to Mac internal speaker in Control Center. The HomePod should disappear from DevicesCapsule (HAL stops reporting it).

- [ ] **Step B.1.5: Commit**

```bash
git add Tutti/AudioDeviceManager.swift
git commit -m "surface active airplay devices via core audio hal"
```

---

## Phase C: AirPlayCapsule UI (only if Phase 0 succeeded)

### Task C.1: AirPlayCapsule + AirPlayRow

**Files:**
- Modify: `Tutti/MenuBarView.swift` (append new structs before `SectionHead`)

- [ ] **Step C.1.1: Read current MenuBarView to find the insertion point**

```bash
cd "/Volumes/990 EP/Dev/tutti"
grep -n "private struct SectionHead\|private struct ProfilesCapsule" Tutti/MenuBarView.swift
```

Find the line just before `private struct SectionHead<Trailing: View>`. That's where the new capsule + row go.

- [ ] **Step C.1.2: Insert AirPlayCapsule + AirPlayRow**

Just before `private struct SectionHead`, insert:

```swift
// MARK: - AirPlay capsule

private struct AirPlayCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var browser: AirPlayBrowser
    @EnvironmentObject var prefs: AppearancePrefs
    @Binding var folded: Bool

    /// Hide AirPlay devices that HAL already surfaces in DevicesCapsule.
    /// The audio device's UID for AirPlay typically encodes its identifier,
    /// but to be safe we also match on normalized name.
    private var displayableDevices: [AirPlayDevice] {
        let halAirPlayUIDs = Set(
            manager.devices
                .filter { $0.transportType == kAudioDeviceTransportTypeAirPlay }
                .map { $0.uid }
        )
        let halAirPlayNames = Set(
            manager.devices
                .filter { $0.transportType == kAudioDeviceTransportTypeAirPlay }
                .map { BluetoothMonitorHelpers.normalizeName($0.name) }
        )
        return browser.devices.filter { device in
            !halAirPlayUIDs.contains(device.id) &&
            !halAirPlayNames.contains(BluetoothMonitorHelpers.normalizeName(device.name))
        }
    }

    var body: some View {
        let visible = displayableDevices
        if visible.isEmpty {
            EmptyView()
        } else {
            GlassCapsule {
                VStack(spacing: 0) {
                    SectionHead(title: "AirPlay",
                                trailing: LocalizedStringKey("\(visible.count)"),
                                folded: $folded)

                    if !folded {
                        VStack(spacing: 2) {
                            ForEach(visible) { device in
                                AirPlayRow(device: device)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                    }
                }
                .padding(4)
            }
        }
    }
}

private struct AirPlayRow: View {
    let device: AirPlayDevice

    var body: some View {
        Button(action: {
            _ = AirPlaySwitcher.switchTo(device)
        }) {
            HStack(spacing: 8) {
                Image(systemName: device.deviceType.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.glassTextHi)
                    .frame(width: 18)
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.glassTextHi)
                Spacer()
                Image(systemName: "airplayaudio")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.glassTextLo)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: innerRowRadius)
                .fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(device.name), AirPlay 设备, 双击切换"))
    }
}
```

**Important**: The dedupe logic references `BluetoothMonitorHelpers.normalizeName(_:)`. This helper exists in `Tutti/BluetoothDeviceMonitor.swift` per the previous (now-abandoned) bluetooth implementation. Since v0.3.1 was reverted, **this helper no longer exists in the codebase**.

If `BluetoothMonitorHelpers.normalizeName` does not exist after the v0.3.1 revert, inline a small equivalent at the top of `Tutti/MenuBarView.swift` (or create `Tutti/NameNormalize.swift`):

```swift
private func normalizeName(_ s: String) -> String {
    s.precomposedStringWithCanonicalMapping.lowercased()
        .components(separatedBy: .whitespacesAndNewlines).joined()
}
```

And replace `BluetoothMonitorHelpers.normalizeName(...)` with `normalizeName(...)` in the dedupe logic.

- [ ] **Step C.1.3: Build to verify**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Likely errors:
- `Color.glassTextHi / Color.glassTextLo` — mirror how `GlassDeviceRow` references colors (likely the same way, no change needed)
- `BluetoothMonitorHelpers` not found — apply the inline helper fix above

### Task C.2: Insert AirPlayCapsule into MenuBarView body

**Files:**
- Modify: `Tutti/MenuBarView.swift`

- [ ] **Step C.2.1: Add the EnvironmentObject and State for fold**

In `struct MenuBarView`, alongside the other `@EnvironmentObject` declarations (around lines 13-18), add:

```swift
    @EnvironmentObject var airPlayBrowser: AirPlayBrowser
    @State private var airPlayFolded = false
```

- [ ] **Step C.2.2: Insert AirPlayCapsule between DevicesCapsule and ProfilesCapsule**

Find the line with `DevicesCapsule(folded: $devicesFolded)` (around line 56-58 of MenuBarView body). Insert after it:

```swift
            DevicesCapsule(folded: $devicesFolded)

            AirPlayCapsule(folded: $airPlayFolded)

            if showProfiles {
                ProfilesCapsule(...)
                ...
            }
```

- [ ] **Step C.2.3: Build to verify**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step C.2.4: Commit Phase C**

```bash
git add Tutti/MenuBarView.swift
git status
git commit -m "add airplay capsule to menubar popover"
```

---

## Phase D: AppDelegate Wiring (only if Phase 0 succeeded)

### Task D.1: Instantiate AirPlayBrowser and wire popover lifecycle

**Files:**
- Modify: `Tutti/AppDelegate.swift`

- [ ] **Step D.1.1: Add the property and wiring**

Read `Tutti/AppDelegate.swift` (it should be ~127 lines after revert). Find the stored properties block (around lines 6-9):

```swift
    private let manager = AudioDeviceManager()
    private let profiles = ProfileStore()
    private let popover = TuttiPopover()
```

Change to:

```swift
    private let manager = AudioDeviceManager()
    private let profiles = ProfileStore()
    private let airPlayBrowser = AirPlayBrowser()
    private let popover = TuttiPopover()
```

In `applicationDidFinishLaunching(_:)`, find the `popover.onVisibilityChange` block (around line 29-31):

```swift
        popover.onVisibilityChange = { [weak manager] visible in
            manager?.setPopoverVisible(visible)
        }
```

Change to:

```swift
        popover.onVisibilityChange = { [weak manager, airPlayBrowser] visible in
            manager?.setPopoverVisible(visible)
            if visible {
                airPlayBrowser.startContinuousScan()
            } else {
                airPlayBrowser.stopContinuousScan()
            }
        }
```

In the same method, find the `rootView` construction chain (around line 19-25):

```swift
        let rootView = MenuBarView()
            .environmentObject(manager)
            .environmentObject(profiles)
            .environment(\.openTuttiSettings, OpenTuttiSettingsAction { [weak self] in
                self?.openSettings()
            })
            .environment(\.tuttiPopover, popover)
```

Change to:

```swift
        let rootView = MenuBarView()
            .environmentObject(manager)
            .environmentObject(profiles)
            .environmentObject(airPlayBrowser)
            .environment(\.openTuttiSettings, OpenTuttiSettingsAction { [weak self] in
                self?.openSettings()
            })
            .environment(\.tuttiPopover, popover)
```

- [ ] **Step D.1.2: Build to verify**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step D.1.3: Commit Phase D**

```bash
git add Tutti/AppDelegate.swift
git status
git commit -m "wire airplay browser into appdelegate and popover lifecycle"
```

---

## Phase E: Localization (only if Phase 0 succeeded)

### Task E.1: Add 4 xcstrings keys with 9-language translations

**Files:**
- Modify: `Tutti/Localizable.xcstrings`

The xcstrings format is JSON. The previous bluetooth phase showed that re-serializing via Python causes massive (cosmetic) diff churn. The cleanest path is to **add new keys via Xcode's String Catalog editor** (which preserves formatting) or use a JSON-aware tool that preserves the existing style.

- [ ] **Step E.1.1: Identify the format**

```bash
head -3 Tutti/Localizable.xcstrings
# Expected: { "sourceLanguage": "zh-Hans", "version": "1.0", "strings": { ... } }
```

- [ ] **Step E.1.2: Add the 4 keys via Xcode editor**

```bash
open Tutti.xcodeproj
```

In Xcode's project navigator, open `Localizable.xcstrings`. Click `+` at the bottom-left to add a new key. Repeat for all 4 keys below, filling in the source (`zh-Hans` column) and `en`, then completing each of the 7 additional language columns.

| Key (zh-Hans source) | en | zh-Hant | ja | ko | fr | de | it | es |
|---|---|---|---|---|---|---|---|---|
| `AirPlay` | `AirPlay` | `AirPlay` | `AirPlay` | `AirPlay` | `AirPlay` | `AirPlay` | `AirPlay` | `AirPlay` |
| `当前` | `Current` | `當前` | `現在` | `현재` | `Actuel` | `Aktuell` | `Attuale` | `Actual` |
| `切换到 %@` | `Switch to %@` | `切換到 %@` | `%@に切り替え` | `%@(으)로 전환` | `Basculer vers %@` | `Zu %@ wechseln` | `Passa a %@` | `Cambiar a %@` |
| `AirPlay 设备 · 当前激活` | `AirPlay device · currently active` | `AirPlay 裝置 · 當前啟用` | `AirPlayデバイス・現在使用中` | `AirPlay 기기 · 현재 활성` | `Appareil AirPlay · actif` | `AirPlay-Gerät · aktiv` | `Dispositivo AirPlay · attivo` | `Dispositivo AirPlay · activo` |

Close and reopen the file in Xcode to confirm saves wrote correctly. Each of the 4 keys should show `9/9 translated`.

- [ ] **Step E.1.3: Build and verify**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step E.1.4: Commit Phase E**

```bash
git add Tutti/Localizable.xcstrings
git diff --stat Tutti/Localizable.xcstrings  # should be small (~50 lines added, not thousands)
git commit -m "translate airplay capsule strings across nine locales"
```

If the diff is unexpectedly large (>500 lines), the Xcode save reformatted the whole file. This is acceptable but noisy — accept the diff or revert and try again with a JSON-preserving tool.

---

## Phase F: Manual Test + Release

### Task F.1: Manual integration test (full scenario walk)

- [ ] **Step F.1.1: Build a Debug installable**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodebuild -project Tutti.xcodeproj -scheme Tutti -configuration Debug \
  -derivedDataPath build/integ build 2>&1 | tail -3
APP=build/integ/Build/Products/Debug/Tutti.app
killall Tutti 2>/dev/null || true
open "$APP"
```

- [ ] **Step F.1.2: Walk the 10-step test from the spec**

Reference: `docs/superpowers/specs/2026-05-27-tutti-v03x-airplay-design.md` → "手测脚本"

1. **首启 HAL 兜底** — system currently routed to a HomePod via Control Center → open Tutti popover → HomePod appears in `DevicesCapsule` with `airplayaudio` symbol
2. **AirPlay 发现** — close all AirPlay routes → open popover → `AirPlayCapsule` shows all LAN AirPlay devices (count visible in section head)
3. **点击切换** — tap HomePod row in AirPlayCapsule → system default output instantly switches to HomePod → HomePod disappears from AirPlayCapsule → reappears in DevicesCapsule (HAL surfaces the active route)
4. **设备类型图标** — HomePod shows `homepod.fill`, Apple TV shows `appletv.fill`, other Mac shows `desktopcomputer`. (Type detection depends on the Phase 0 path's metadata exposure — if device type is unknown, falls back to `airplayaudio`.)
5. **去重正确** — after switching to HomePod, HomePod appears in only DevicesCapsule, never in both at once
6. **切回本地** — in DevicesCapsule, uncheck the HomePod → system output returns to local → HomePod disappears from DevicesCapsule → reappears in AirPlayCapsule
7. **同名设备 / 朋友家 HomePod** — if a neighbor's HomePod is reachable, it appears in AirPlayCapsule alongside yours; tapping it should attempt to switch (may fail silently — acceptable per spec)
8. **空 LAN** — turn off Wi-Fi → open popover → AirPlayCapsule disappears (hidden because devices=[])
9. **macOS 升级模拟** — temporarily edit `Tutti/AirPlayBrowser.swift` `startContinuousScan` to early-return (simulate reflection failing) → rebuild → open popover → AirPlayCapsule hidden, DevicesCapsule fallback still works → **revert the edit before continuing**
10. **app 退出清理** — open popover → killall Tutti → `ps aux | grep -i airplay` returns no Tutti-launched discovery services

- [ ] **Step F.1.3: Fix any failed steps**

For each failure: identify the cause, edit the relevant file, re-run the failing step. Common likely failures:
- AirPlay device type detection is wrong → adjust `AirPlayDeviceType.from(rawType:)` mapping
- Dedupe miss between HAL and browser → tighten normalize matching
- AirPlayCapsule renders with `0` count instead of hiding → check `displayableDevices.isEmpty` guard

After fixes, re-run the affected steps until all 10 pass.

- [ ] **Step F.1.4: Commit any fixes**

```bash
git status
git add -p
git commit -m "fix airplay integration issues from manual testing"
```

(Skip if no fixes.)

### Task F.2: Version bump

**Files:**
- Modify: `project.yml`

- [ ] **Step F.2.1: Bump CFBundleShortVersionString and CFBundleVersion**

Pick the version number based on Phase 0 outcome:
- **Phase 0 succeeded → v0.3.0** (full AirPlay shortcut entry)
- **Phase 0 failed → v0.2.2** (minor: HAL-only AirPlay surface)

For v0.3.0:
```bash
cd "/Volumes/990 EP/Dev/tutti"
/usr/bin/sed -i '' \
  -e 's/CFBundleShortVersionString: "0.2.1"/CFBundleShortVersionString: "0.3.0"/' \
  -e 's/CFBundleVersion: "3"/CFBundleVersion: "4"/' \
  project.yml
grep "CFBundleShort\|CFBundleVersion:" project.yml
```

For v0.2.2:
```bash
/usr/bin/sed -i '' \
  -e 's/CFBundleShortVersionString: "0.2.1"/CFBundleShortVersionString: "0.2.2"/' \
  -e 's/CFBundleVersion: "3"/CFBundleVersion: "4"/' \
  project.yml
```

- [ ] **Step F.2.2: Regenerate**

```bash
xcodegen generate
grep "CFBundleShort\|CFBundleVersion" Tutti/Info.plist
```

### Task F.3: Release pipeline

- [ ] **Step F.3.1: Pre-release dry run**

Comment out the `gh release create ...` block in `scripts/release.sh` temporarily, then run:

```bash
cd "/Volumes/990 EP/Dev/tutti"
./scripts/release.sh
```

Expected: archive succeeds, export succeeds, verify signature passes, notarize accepted, staple validates. Build artifact at `build/release/Tutti-<version>.zip`.

- [ ] **Step F.3.2: Restore release.sh and prepare to publish**

Un-comment the `gh release create` block.

```bash
git diff scripts/release.sh
# Should show no diff vs main now
```

- [ ] **Step F.3.3: Stage the version bump commit**

```bash
git add project.yml Tutti.xcodeproj Tutti/Info.plist
git status
git commit -m "bump version to <0.3.0|0.2.2> for airplay release"
```

- [ ] **Step F.3.4: Confirm with user before publishing**

**This is a destructive operation per the user's global rules — get explicit confirmation before proceeding.** Surface the staged state to the user and wait for explicit "yes, publish" before running the next step.

- [ ] **Step F.3.5: Publish**

After user confirmation:

```bash
cd "/Volumes/990 EP/Dev/tutti"
git push origin main
./scripts/release.sh
```

This creates the tag and pushes the GitHub release.

- [ ] **Step F.3.6: Verify release URL in browser**

The script prints the release URL on completion. Open it to confirm.

---

## Self-Review (writing-plans skill checklist)

**Spec coverage:**
- Spec §"Lockedin decisions" → reflected throughout (Free, no state machine, no auto-restore, etc.)
- Spec §"Phase 0 Spike" → Tasks 0.1 through 0.7
- Spec §"Spike 5 项验证清单" → Step 0.2.4 / 0.3.3 / 0.4.3 / 0.6.1 reference checklist
- Spec §"架构总览" → Tasks A.1-A.4 implement the two decoupled units
- Spec §"数据模型" → Task A.1
- Spec §"发现层 AirPlayBrowser" → Task A.3
- Spec §"切换层 AirPlaySwitcher" → Task A.2
- Spec §"UI 设计 + 去重" → Tasks C.1 + C.2
- Spec §"错误处理 + 边界 case" → covered by os_log + silent degrade in A.2/A.3 + dedupe in C.1
- Spec §"测试 / 手测脚本" → Task F.1
- Spec §"工期" → matches Phase 0-F breakdown
- Spec §"Phase 0 决策点" → Tasks 0.6 (success) / 0.7 (fail)
- Spec §"风险" → mitigated by Tasks A.5 (early notarize), A.6 (smoke test), 0.7 (downscope fallback)

**Placeholder scan:**
- The AirPlayBrowser.swift implementation in A.3.4 contains commented-out patterns P1/P2/P3 with "implementer fills in based on Phase 0 outcome" — this is intentional and not a placeholder; the spike result determines the concrete code. The plan explicitly says do not ship the no-op version.
- All other tasks have complete code, exact commands, expected outputs.

**Type consistency:**
- `AirPlayDevice` used consistently across A.1, A.2, A.3, C.1
- `AirPlayDeviceType` used in A.1 and C.1
- `AirPlayBrowser.shared` / `AirPlayBrowser()` — A.2 uses `.shared`, A.3 defines both `shared` singleton and standalone instantiation. AppDelegate D.1 uses standalone (`AirPlayBrowser()`) — and the `.shared` in A.2 is purely the lookup convenience for the switcher; consistent.
- `rawDevice(forID:)` consistent between A.2 (caller) and A.3 (implementation)
- `BluetoothMonitorHelpers.normalizeName` referenced in C.1 with a fallback path if the helper doesn't exist after v0.3.1 revert — flagged and handled

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-27-tutti-v03x-airplay.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
