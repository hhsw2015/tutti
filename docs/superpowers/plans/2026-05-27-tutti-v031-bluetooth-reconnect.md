# Tutti v0.3.1 Bluetooth Reconnect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.3.1 of Tutti with paired-Bluetooth device discovery + one-click reconnect, all gated behind the bundled `blueutil` CLI subprocess (zero `IOBluetooth` linkage in main process).

**Architecture:** Main process discovers paired devices via `/usr/sbin/system_profiler SPBluetoothDataType -json` (no TCC trigger) and reconnects via a bundled, codesigned `blueutil` subprocess (TCC permission inherited from main app's `NSBluetoothAlwaysUsageDescription`). Successful reconnect notifies `AudioDeviceManager` to merge the device into the existing multi-output aggregate. No default-output switching.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, CoreAudio, Foundation `Process`, Combine, `system_profiler` (Apple), `blueutil` v2.13.0 (MIT)

**Spec:** `docs/superpowers/specs/2026-05-27-tutti-v031-bluetooth-design.md`

**Prerequisites:**
- macOS 13+ build environment
- Xcode 15+ with Developer ID signing identity `Developer ID Application: BaoLin Wu (RFW398ARA9)`
- `xcodegen` + `notarytool` configured (keychain profile `tutti-notary`)
- `brew install blueutil` already done (verified during spike)
- Local TuttiTests target overlay (the gitignored `TuttiTests/` directory already exists for license tests). If `xcodebuild test` is not currently working locally, restore the test target via a local `project.tests.yml` overlay before Phase 2.

---

## File Structure

**New files (committed)**:
- `Tutti/BluetoothDeviceMonitor.swift` — `@MainActor ObservableObject`: discovery, state machine, Core Audio handoff
- `Tutti/BluetoothReconnector.swift` — `actor`: blueutil subprocess wrapper, 5s timeout, process cleanup
- `Tutti/Resources/bin/blueutil` — bundled binary (arm64, ~149KB; universal can come later)
- `scripts/blueutil.version` — SHA256 + upstream version manifest (supply-chain audit trail)
- `scripts/verify-bluetooth.sh` — pre-flight smoke test (post-build, before release)

**New files (local-only, gitignored under `TuttiTests/`)**:
- `TuttiTests/SystemProfilerParseTests.swift`
- `TuttiTests/BluetoothRowStateTests.swift`
- `TuttiTests/BluetoothMonitorReconnectTests.swift`
- `TuttiTests/AudioDeviceManagerHookTests.swift`
- `TuttiTests/Fixtures/system_profiler_bluetooth.json` (test fixture)

**Modified files**:
- `Tutti/AudioDeviceManager.swift` — `+onBluetoothConnected: ((String) -> Void)?` hook, `+handleBluetoothConnected(name:)`, `+addToSelection(_:)`
- `Tutti/MenuBarView.swift` — `+BluetoothCapsule` + `+BluetoothRow`, insert into `body` between `DevicesCapsule` and `ProfilesCapsule`
- `Tutti/AppDelegate.swift` — instantiate `BluetoothDeviceMonitor`, wire into env, fire `warm()` in `applicationDidFinishLaunching`
- `Tutti/Localizable.xcstrings` — 4 new keys × 9 languages
- `project.yml` — `NSBluetoothAlwaysUsageDescription` plist entry + `resources` declaration for `blueutil`
- `scripts/release.sh` — codesign blueutil before main app, verify after

---

## Phase 1: Bundled blueutil Spike (CRITICAL GATE)

**Goal:** Prove that a `Developer ID Application`-signed `blueutil` bundled inside a Hardened-Runtime `.app` can request and use Bluetooth permission via the standard macOS TCC consent flow. If this fails, the entire approach must be reconsidered.

### Task 1.1: Pin and stage the blueutil binary

**Files:**
- Create: `Tutti/Resources/bin/blueutil`
- Create: `scripts/blueutil.version`

- [ ] **Step 1.1.1: Create the resources directory and copy blueutil**

```bash
cd "/Volumes/990 EP/Dev/tutti"
mkdir -p Tutti/Resources/bin
cp /opt/homebrew/bin/blueutil Tutti/Resources/bin/blueutil
chmod +x Tutti/Resources/bin/blueutil
```

- [ ] **Step 1.1.2: Verify architecture and write version manifest**

```bash
ARCH=$(lipo -archs Tutti/Resources/bin/blueutil)
VERSION=$(./Tutti/Resources/bin/blueutil --version)
SHA256=$(shasum -a 256 Tutti/Resources/bin/blueutil | awk '{print $1}')
cat > scripts/blueutil.version <<EOF
upstream: https://github.com/toy/blueutil
version: ${VERSION}
arch: ${ARCH}
sha256: ${SHA256}
acquired: $(date -u +%Y-%m-%dT%H:%M:%SZ) via brew install blueutil
note: arm64 only for v0.3.1; rebuild universal for v0.3.2+ if Intel users surface
EOF
cat scripts/blueutil.version
```

Expected:
```
upstream: https://github.com/toy/blueutil
version: 2.13.0
arch: arm64
sha256: <64-hex>
acquired: 2026-05-27T...
note: arm64 only for v0.3.1; rebuild universal for v0.3.2+ if Intel users surface
```

- [ ] **Step 1.1.3: Smoke-test the staged binary**

```bash
./Tutti/Resources/bin/blueutil --paired | head -3
```

Expected: either device list output (if Terminal already has Bluetooth permission) or `Received abort signal...` error (TCC denial). Either is fine — we're just verifying the binary itself runs.

### Task 1.2: Wire blueutil into project.yml as a bundled resource

**Files:**
- Modify: `project.yml`

- [ ] **Step 1.2.1: Add NSBluetoothAlwaysUsageDescription and resources entry**

Edit `project.yml`. Under `targets.Tutti.info.properties`, append:

```yaml
        NSBluetoothAlwaysUsageDescription: "Tutti needs Bluetooth to reconnect your paired headphones and speakers."
```

Under `targets.Tutti`, add a `resources:` key sibling to `sources:`:

```yaml
    resources:
      - path: Tutti/Resources/bin
        type: folder
```

Final `targets.Tutti` block should look like (relevant portions):

```yaml
targets:
  Tutti:
    type: application
    platform: macOS
    sources:
      - path: Tutti
        excludes:
          - "**/*.plist"
          - "**/*.entitlements"
    resources:
      - path: Tutti/Resources/bin
        type: folder
    info:
      path: Tutti/Info.plist
      properties:
        CFBundleName: Tutti
        CFBundleDisplayName: Tutti
        CFBundleShortVersionString: "0.2.1"
        CFBundleVersion: "3"
        LSUIElement: YES
        NSHumanReadableCopyright: ""
        NSBluetoothAlwaysUsageDescription: "Tutti needs Bluetooth to reconnect your paired headphones and speakers."
        CFBundleDevelopmentRegion: zh-Hans
        ...
```

- [ ] **Step 1.2.2: Regenerate Xcode project**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodegen generate
```

Expected: "Generated project successfully" + no errors. Open `Tutti.xcodeproj` and confirm `Tutti/Resources/bin/blueutil` appears under the file tree.

- [ ] **Step 1.2.3: Build and verify blueutil is in the .app bundle**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti -configuration Debug \
  -derivedDataPath build/spike build 2>&1 | tail -5
ls build/spike/Build/Products/Debug/Tutti.app/Contents/Resources/bin/blueutil
```

Expected: file exists. Note: with `type: folder`, the binary lands at `Contents/Resources/bin/blueutil`. If it lands at `Contents/Resources/blueutil` instead, switch `type: folder` to `type: file` and adjust the Swift bundle lookup later.

### Task 1.3: Pre-flight verify-bluetooth.sh

**Files:**
- Create: `scripts/verify-bluetooth.sh`

- [ ] **Step 1.3.1: Write the script**

```bash
cat > "/Volumes/990 EP/Dev/tutti/scripts/verify-bluetooth.sh" <<'EOF'
#!/usr/bin/env bash
# Pre-flight check: confirm bundled blueutil in a built Tutti.app can list
# paired devices. Run after a Debug or Release build, before pushing a release.
#
# Usage:
#   ./scripts/verify-bluetooth.sh [path-to-Tutti.app]
#
# Default path: build/spike/Build/Products/Debug/Tutti.app

set -euo pipefail

APP_PATH="${1:-build/spike/Build/Products/Debug/Tutti.app}"
BLUEUTIL="$APP_PATH/Contents/Resources/bin/blueutil"

if [ ! -x "$BLUEUTIL" ]; then
  echo "FAIL: bundled blueutil not found or not executable at $BLUEUTIL" >&2
  exit 1
fi

echo "==> blueutil path: $BLUEUTIL"
echo "==> codesign info:"
codesign -dv --verbose=2 "$BLUEUTIL" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime|Signature" || true

echo "==> Calling blueutil --paired (first 5 lines):"
"$BLUEUTIL" --paired 2>&1 | head -5

echo "==> SUCCESS if device list above; FAIL if 'Received abort signal' or codesign issue."
EOF
chmod +x "/Volumes/990 EP/Dev/tutti/scripts/verify-bluetooth.sh"
```

- [ ] **Step 1.3.2: First run (unsigned) — should reveal Debug signing**

```bash
cd "/Volumes/990 EP/Dev/tutti"
./scripts/verify-bluetooth.sh
```

Expected: codesign info shows Debug ad-hoc signing (or no Authority). `blueutil --paired` likely returns "Received abort signal..." because Debug builds aren't Developer ID signed. **This is normal**; the real test happens in Task 1.5 with a Release build.

### Task 1.4: Add blueutil signing step to release.sh (scaffolding only)

**Files:**
- Modify: `scripts/release.sh`

- [ ] **Step 1.4.1: Insert codesign for blueutil before main app verify**

Edit `scripts/release.sh`. Locate the line `echo "==> Verify signature"` (right after `xcodebuild -exportArchive ...`). Insert above it:

```bash
echo "==> Codesign bundled blueutil"
codesign --force --sign "$SIGN_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements /dev/null \
  "$APP_PATH/Contents/Resources/bin/blueutil"
codesign --verify --verbose "$APP_PATH/Contents/Resources/bin/blueutil"
```

Then re-verify the main app (existing logic):

```bash
echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime"
```

The `--deep --strict` verify will now also walk into the nested binary. If `blueutil` isn't properly signed first, this will fail.

### Task 1.5: Release-grade spike — sign, notarize, install, verify TCC

**Files:** (no source changes, but produces real `.app`)

- [ ] **Step 1.5.1: Run a temporary Release build with signing (no GitHub publish)**

This is a manual operation that exercises real signing + notarization. **Skip the gh release publish step.** Edit `scripts/release.sh` temporarily to comment out the `gh release create ...` line, or extract the relevant pieces:

```bash
cd "/Volumes/990 EP/Dev/tutti"

BUILD_DIR="build/spike-release"
ARCHIVE="$BUILD_DIR/Tutti.xcarchive"
EXPORT="$BUILD_DIR/export"
APP="$EXPORT/Tutti.app"
SIGN_IDENTITY="Developer ID Application: BaoLin Wu (RFW398ARA9)"

rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

xcodebuild -project Tutti.xcodeproj -scheme Tutti -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" archive

cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
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

codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
  --entitlements /dev/null \
  "$APP/Contents/Resources/bin/blueutil"

codesign --verify --deep --strict --verbose=2 "$APP"
```

Expected: `valid on disk` + `satisfies its Designated Requirement` from final verify.

- [ ] **Step 1.5.2: Notarize the spike build**

```bash
ZIP="$BUILD_DIR/Tutti-spike.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "tutti-notary" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
```

Expected: `status: Accepted` + `The staple and validate action worked!`. If notarize rejects, read the log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "tutti-notary"
```

Most likely failure mode: blueutil missing `--options runtime`. The codesign step above includes it.

- [ ] **Step 1.5.3: Install and trigger TCC**

```bash
# Install spike build (don't overwrite installed Tutti permanently)
rm -rf /tmp/Tutti.app
cp -R "$APP" /tmp/Tutti.app
xattr -dr com.apple.quarantine /tmp/Tutti.app  # avoid Gatekeeper prompt
tccutil reset Bluetooth com.recents.tutti 2>/dev/null || true

# Open it
open /tmp/Tutti.app
```

Then manually trigger a blueutil call. Since the production code isn't written yet, run the bundled binary directly through Tutti's bundle ID context. Easiest method: from a Terminal that has Bluetooth permission, run the bundled binary directly:

```bash
/tmp/Tutti.app/Contents/Resources/bin/blueutil --paired | head -5
```

This proves the **signing chain is intact**. The full "main app prompts for Bluetooth" flow gets exercised in Phase 3 once Swift code calls `BlueutilLauncher.binaryURL`.

**The critical signal:** the codesign chain holds + notarize accepts + bundled blueutil runs without "killed: 9" or "code signature invalid". If any of those fail, stop and reassess approach.

- [ ] **Step 1.5.4: Revert any temporary changes to release.sh**

If you commented out `gh release create ...` in Step 1.5.1, revert it. The Task 1.4 codesign insertion should remain.

```bash
cd "/Volumes/990 EP/Dev/tutti"
git diff scripts/release.sh  # should show only the Task 1.4 codesign block
```

### Task 1.6: Commit Phase 1

- [ ] **Step 1.6.1: Stage and commit**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add Tutti/Resources/bin/blueutil scripts/blueutil.version \
  scripts/verify-bluetooth.sh scripts/release.sh project.yml \
  Tutti.xcodeproj
git status  # sanity check — should NOT include build/ or DerivedData/
git commit -m "bundle blueutil for v0.3.1 bluetooth reconnect"
```

---

## Phase 2: BluetoothReconnector + BluetoothDeviceMonitor

**Goal:** Core Swift types: subprocess wrapper actor, parsed device list, state machine. All testable in isolation.

### Task 2.1: Create BluetoothReconnector actor

**Files:**
- Create: `Tutti/BluetoothReconnector.swift`
- Create: `TuttiTests/BluetoothReconnectorTests.swift` (local-only)

- [ ] **Step 2.1.1: Write failing test for blueutil subprocess success**

Create `TuttiTests/BluetoothReconnectorTests.swift`:

```swift
import XCTest
@testable import Tutti

final class BluetoothReconnectorTests: XCTestCase {
    /// Uses /bin/echo as a stand-in subprocess that exits 0 immediately.
    /// We're testing the actor's process plumbing, not the real blueutil semantics.
    func testEchoSubprocessExitsCleanly() async {
        let reconnector = BluetoothReconnector(binaryURL: URL(fileURLWithPath: "/bin/echo"))
        let result = await reconnector.reconnect(macAddress: "00-00-00-00-00-00", timeout: 2)
        switch result {
        case .connected, .timedOut:
            // echo exits 0 quickly. Depending on how reconnect interprets
            // "process exited 0 before timeout" it should land on either.
            // Our contract: subprocess exit 0 == .connected.
            if case .connected = result { return }
            XCTFail("expected .connected for clean exit, got \(result)")
        case .blueutilFailed:
            XCTFail("echo should not fail")
        }
    }
}
```

- [ ] **Step 2.1.2: Run failing test**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/BluetoothReconnectorTests 2>&1 | tail -10
```

Expected: compile failure (`BluetoothReconnector` not defined).

- [ ] **Step 2.1.3: Implement BluetoothReconnector**

Create `Tutti/BluetoothReconnector.swift`:

```swift
import Foundation

/// Subprocess wrapper around the bundled `blueutil` binary. Owns process
/// lifecycle: starts blueutil with --connect, enforces a hard timeout, and
/// terminates the child cleanly. No IOBluetooth linkage in this actor — that
/// is the entire point of the design.
actor BluetoothReconnector {
    enum Result: Equatable {
        case connected
        case timedOut
        case blueutilFailed(stderr: String)
    }

    private let binaryURL: URL

    init(binaryURL: URL = BlueutilLauncher.binaryURL) {
        self.binaryURL = binaryURL
    }

    func reconnect(macAddress: String, timeout: TimeInterval = 5) async -> Result {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--connect", macAddress]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .blueutilFailed(stderr: "failed to spawn: \(error.localizedDescription)")
        }

        // Race timeout vs natural exit. The detached task awaits process
        // termination via waitUntilExit (blocking, so on a thread).
        let exitTask = Task.detached(priority: .userInitiated) { () -> Int32 in
            process.waitUntilExit()
            return process.terminationStatus
        }
        let timeoutTask = Task.detached(priority: .userInitiated) { () -> Bool in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return Task.isCancelled
        }

        // Whoever finishes first wins. exitTask resolving cancels timeoutTask.
        return await withTaskGroup(of: Result.self) { group in
            group.addTask {
                let code = await exitTask.value
                if code == 0 { return .connected }
                let errData = errPipe.fileHandleForReading.availableData
                let stderr = String(data: errData, encoding: .utf8) ?? "exit code \(code)"
                return .blueutilFailed(stderr: stderr)
            }
            group.addTask {
                _ = await timeoutTask.value
                if process.isRunning {
                    process.terminate()
                    return .timedOut
                }
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }
}

/// Locates the bundled blueutil binary inside Tutti.app.
struct BlueutilLauncher {
    static var binaryURL: URL {
        guard let url = Bundle.main.url(
            forResource: "blueutil",
            withExtension: nil,
            subdirectory: "bin"
        ) else {
            fatalError("blueutil missing from bundle — release script is broken")
        }
        return url
    }
}
```

- [ ] **Step 2.1.4: Run test to verify it passes**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/BluetoothReconnectorTests 2>&1 | tail -10
```

Expected: `Test Suite 'BluetoothReconnectorTests' passed`.

- [ ] **Step 2.1.5: Add a timeout test**

Append to `TuttiTests/BluetoothReconnectorTests.swift`:

```swift
    /// Uses /bin/sleep with a long duration to force timeout path.
    func testTimeoutTerminatesSubprocess() async {
        let reconnector = BluetoothReconnector(binaryURL: URL(fileURLWithPath: "/bin/sleep"))
        let start = Date()
        let result = await reconnector.reconnect(macAddress: "30", timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(elapsed, 2.5, "timeout did not fire promptly")
    }
```

- [ ] **Step 2.1.6: Run and verify**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/BluetoothReconnectorTests 2>&1 | tail -10
```

Expected: both tests pass.

### Task 2.2: PairedBluetoothDevice + BluetoothRowState data models

**Files:**
- Create: `Tutti/BluetoothDeviceMonitor.swift` (initial scaffold with types only)

- [ ] **Step 2.2.1: Define data models**

Create `Tutti/BluetoothDeviceMonitor.swift`:

```swift
import Foundation
import Combine

struct PairedBluetoothDevice: Identifiable, Equatable, Hashable {
    /// Normalized MAC (lowercased, hyphens preserved). Stable across launches.
    let id: String
    let name: String
    /// Original-case MAC from system_profiler. Passed verbatim to blueutil.
    let macAddress: String
    let isConnected: Bool
    let batteryLevel: Int?
    /// Raw `device_minorType` from system_profiler. Used to pick the SF Symbol.
    let minorType: String?

    static func normalizeMAC(_ raw: String) -> String {
        raw.lowercased()
    }
}

enum BluetoothRowState: Equatable {
    case idle
    case connecting(deadline: Date)
    case failed(until: Date)
}

/// System_profiler reports a variety of `device_minorType` values. We only
/// surface audio outputs; the rest (keyboards, watches, phones, ...) get
/// filtered out of the BluetoothCapsule.
enum BluetoothAudioType {
    static let audioMinorTypes: Set<String> = [
        "Headphones", "Headset", "Speakers", "Carkit", "AudioDevice"
    ]
    static func isAudio(_ minorType: String?) -> Bool {
        guard let m = minorType else { return false }
        return audioMinorTypes.contains(m)
    }
}
```

- [ ] **Step 2.2.2: Verify it compiles**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

### Task 2.3: SystemProfiler JSON parser

**Files:**
- Create: `TuttiTests/Fixtures/system_profiler_bluetooth.json` (local-only)
- Create: `TuttiTests/SystemProfilerParseTests.swift` (local-only)
- Modify: `Tutti/BluetoothDeviceMonitor.swift`

- [ ] **Step 2.3.1: Capture a real fixture**

```bash
mkdir -p "/Volumes/990 EP/Dev/tutti/TuttiTests/Fixtures"
/usr/sbin/system_profiler SPBluetoothDataType -json \
  > "/Volumes/990 EP/Dev/tutti/TuttiTests/Fixtures/system_profiler_bluetooth.json"
head -50 "/Volumes/990 EP/Dev/tutti/TuttiTests/Fixtures/system_profiler_bluetooth.json"
```

Confirm it has both `device_connected` and `device_not_connected` sub-arrays. If your machine has zero connected devices currently, manually edit the JSON to ensure both arrays appear (you can copy entries between arrays).

- [ ] **Step 2.3.2: Write failing parse test**

Create `TuttiTests/SystemProfilerParseTests.swift`:

```swift
import XCTest
@testable import Tutti

final class SystemProfilerParseTests: XCTestCase {
    private func loadFixture() throws -> Data {
        let url = Bundle(for: type(of: self))
            .url(forResource: "system_profiler_bluetooth", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testParsesConnectedAndDisconnectedAudioDevices() throws {
        let data = try loadFixture()
        let devices = BluetoothDeviceMonitor.parsePairedDevices(from: data)

        XCTAssertFalse(devices.isEmpty, "fixture should contain at least one paired device")

        // All returned devices must be audio types
        for device in devices {
            XCTAssertTrue(BluetoothAudioType.isAudio(device.minorType),
                          "non-audio device leaked through: \(device.name)")
        }
    }

    func testFiltersNonAudioMinorTypes() throws {
        // Construct an inline JSON with one Headphones + one Keyboard
        let json = """
        {
          "SPBluetoothDataType": [{
            "device_not_connected": [
              {"My Headphones": {"device_address": "AA-BB-CC-DD-EE-FF", "device_minorType": "Headphones"}},
              {"My Keyboard":   {"device_address": "11-22-33-44-55-66", "device_minorType": "Keyboard"}}
            ]
          }]
        }
        """.data(using: .utf8)!
        let devices = BluetoothDeviceMonitor.parsePairedDevices(from: json)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.name, "My Headphones")
    }

    func testHandlesMalformedJSON() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertEqual(BluetoothDeviceMonitor.parsePairedDevices(from: bad), [])
    }
}
```

- [ ] **Step 2.3.3: Run failing test**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/SystemProfilerParseTests 2>&1 | tail -10
```

Expected: compile failure (`parsePairedDevices` not defined).

- [ ] **Step 2.3.4: Implement parser as a static method**

Append to `Tutti/BluetoothDeviceMonitor.swift`:

```swift
extension BluetoothDeviceMonitor {
    /// Static parser kept testable in isolation. Filters non-audio minor types.
    /// On any structural surprise, returns whatever it could parse; never crashes.
    static func parsePairedDevices(from data: Data) -> [PairedBluetoothDevice] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else {
            return []
        }

        var devices: [PairedBluetoothDevice] = []
        for controller in controllers {
            for (key, isConnected) in [("device_connected", true), ("device_not_connected", false)] {
                guard let list = controller[key] as? [[String: Any]] else { continue }
                for entry in list {
                    for (name, info) in entry {
                        guard let dict = info as? [String: Any] else { continue }
                        let minorType = dict["device_minorType"] as? String
                        guard BluetoothAudioType.isAudio(minorType) else { continue }
                        guard let macRaw = dict["device_address"] as? String else { continue }
                        let id = PairedBluetoothDevice.normalizeMAC(macRaw)
                        let battery = batteryFromDict(dict)
                        devices.append(PairedBluetoothDevice(
                            id: id,
                            name: name,
                            macAddress: macRaw,
                            isConnected: isConnected,
                            batteryLevel: battery,
                            minorType: minorType
                        ))
                    }
                }
            }
        }
        return devices
    }

    private static func batteryFromDict(_ dict: [String: Any]) -> Int? {
        // Same convention as BluetoothBattery: lowest of Left/Right/Main (excl. Case)
        let prefix = "device_batteryLevel"
        let excludedSuffix = "Case"
        let levels: [Int] = dict.compactMap { key, value in
            guard key.hasPrefix(prefix), !key.hasSuffix(excludedSuffix),
                  let s = value as? String else { return nil }
            return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        }
        return levels.min()
    }
}
```

- [ ] **Step 2.3.5: Run tests to verify they pass**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/SystemProfilerParseTests 2>&1 | tail -10
```

Expected: all three tests pass. If `testParsesConnectedAndDisconnectedAudioDevices` fails because your machine has no audio devices paired, edit the fixture to add a fake Headphones entry.

### Task 2.4: BluetoothDeviceMonitor — discovery + refresh

**Files:**
- Modify: `Tutti/BluetoothDeviceMonitor.swift`

- [ ] **Step 2.4.1: Add the ObservableObject body**

Replace the top of `Tutti/BluetoothDeviceMonitor.swift` (above the existing structs) with the imports and class skeleton, keeping the data models below:

```swift
import Foundation
import Combine

@MainActor
final class BluetoothDeviceMonitor: ObservableObject {
    @Published private(set) var pairedDevices: [PairedBluetoothDevice] = []
    @Published private(set) var rowStates: [String: BluetoothRowState] = [:]

    /// Called when a reconnect attempt succeeds + Core Audio has had ~1.5s to
    /// register the device. AudioDeviceManager subscribes to this.
    var onConnected: ((String) -> Void)?

    /// Closure that supplies the AudioDevice name set currently in Core Audio.
    /// Used to filter out devices that are already in DevicesCapsule.
    var hostedDeviceNames: () -> Set<String> = { [] }

    private var reconnectTasks: [String: Task<Void, Never>] = [:]

    /// Background warm pull at app launch. Non-throwing, no-op on failure.
    func warm() async {
        await refresh()
    }

    /// Re-pull system_profiler and update pairedDevices.
    func refresh() async {
        let data = await Self.runSystemProfiler()
        let devices = Self.parsePairedDevices(from: data)
        self.pairedDevices = devices
    }

    /// Visible-in-UI subset: not currently connected AND not already in Core Audio HAL.
    var displayableDevices: [PairedBluetoothDevice] {
        let hostedNormalized = Set(hostedDeviceNames().map { BluetoothMonitorHelpers.normalizeName($0) })
        return pairedDevices.filter { device in
            !device.isConnected &&
            !hostedNormalized.contains(BluetoothMonitorHelpers.normalizeName(device.name))
        }
    }

    private static func runSystemProfiler() async -> Data {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return pipe.fileHandleForReading.readDataToEndOfFile()
            } catch {
                return Data()
            }
        }.value
    }
}

enum BluetoothMonitorHelpers {
    /// Same convention as BluetoothBattery.normalize but kept here to keep the
    /// monitor self-contained.
    static func normalizeName(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
```

(The data model structs `PairedBluetoothDevice`, `BluetoothRowState`, `BluetoothAudioType` from Task 2.2 stay below.)

- [ ] **Step 2.4.2: Build and verify**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

### Task 2.5: BluetoothDeviceMonitor — reconnect state machine

**Files:**
- Modify: `Tutti/BluetoothDeviceMonitor.swift`
- Create: `TuttiTests/BluetoothRowStateTests.swift` (local-only)

- [ ] **Step 2.5.1: Write failing state-machine test**

Create `TuttiTests/BluetoothRowStateTests.swift`:

```swift
import XCTest
@testable import Tutti

@MainActor
final class BluetoothRowStateTests: XCTestCase {
    func testInitialIdleThenConnectingAfterReconnectKickoff() async {
        let monitor = BluetoothDeviceMonitor()
        // Inject a fake reconnector that resolves .timedOut quickly so the
        // state machine reaches .failed in test time without real bluetooth.
        let fake = FakeReconnector(result: .timedOut, delay: 0.2)
        monitor.reconnectorOverride = { _ in fake }

        let device = PairedBluetoothDevice(
            id: "aa-bb-cc-dd-ee-ff",
            name: "Test Headphones",
            macAddress: "AA-BB-CC-DD-EE-FF",
            isConnected: false,
            batteryLevel: nil,
            minorType: "Headphones"
        )

        let task = Task { await monitor.reconnect(device) }
        // Give the state machine a tick to set .connecting
        try? await Task.sleep(nanoseconds: 50_000_000)
        if case .connecting = monitor.rowStates[device.macAddress] {
            // pass
        } else {
            XCTFail("expected .connecting after kickoff, got \(String(describing: monitor.rowStates[device.macAddress]))")
        }
        await task.value

        // After failure, state should be .failed for ~3s
        if case .failed = monitor.rowStates[device.macAddress] {
            // pass
        } else {
            XCTFail("expected .failed after timeout, got \(String(describing: monitor.rowStates[device.macAddress]))")
        }
    }
}

/// Local test double for BluetoothReconnector. Returns a fixed result after a delay.
actor FakeReconnector {
    let result: BluetoothReconnector.Result
    let delay: TimeInterval
    init(result: BluetoothReconnector.Result, delay: TimeInterval) {
        self.result = result
        self.delay = delay
    }
    func reconnect(macAddress: String, timeout: TimeInterval) async -> BluetoothReconnector.Result {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return result
    }
}
```

- [ ] **Step 2.5.2: Run failing test**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/BluetoothRowStateTests 2>&1 | tail -10
```

Expected: compile failure (`reconnect`, `reconnectorOverride` not defined).

- [ ] **Step 2.5.3: Implement reconnect() with state machine**

Append to `BluetoothDeviceMonitor` class body (inside the class, before the closing brace):

```swift
    /// Test seam: lets unit tests substitute the real BluetoothReconnector
    /// with a stub. In production, defaults to a real reconnector keyed off
    /// the bundled blueutil path.
    var reconnectorOverride: ((String) -> Any)?

    private func makeReconnector(mac: String) -> Any {
        if let make = reconnectorOverride { return make(mac) }
        return BluetoothReconnector()
    }

    func reconnect(_ device: PairedBluetoothDevice) async {
        let mac = device.macAddress

        // Idempotency: a second tap on the same row mid-connecting cancels.
        if let inFlight = reconnectTasks[mac] {
            inFlight.cancel()
            reconnectTasks[mac] = nil
            rowStates[mac] = .idle
            return
        }

        rowStates[mac] = .connecting(deadline: Date().addingTimeInterval(5))
        let task = Task { [weak self] in
            await self?.runReconnect(device: device)
        }
        reconnectTasks[mac] = task
        await task.value
        reconnectTasks[mac] = nil
    }

    private func runReconnect(device: PairedBluetoothDevice) async {
        let mac = device.macAddress
        let reconnector = makeReconnector(mac: mac)

        // Fire-and-forget the subprocess; we make the success determination
        // via polling system_profiler, not via blueutil's exit code.
        let subprocessTask = Task.detached(priority: .userInitiated) { () -> BluetoothReconnector.Result in
            if let stub = reconnector as? FakeReconnectorProtocol {
                return await stub.reconnect(macAddress: mac, timeout: 5)
            }
            return await (reconnector as! BluetoothReconnector).reconnect(macAddress: mac, timeout: 5)
        }

        // Poll system_profiler every 0.5s up to 5s.
        let pollDeadline = Date().addingTimeInterval(5)
        while Date() < pollDeadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { break }
            await refresh()
            if pairedDevices.first(where: { $0.macAddress == mac })?.isConnected == true {
                rowStates[mac] = .idle
                subprocessTask.cancel()
                await scheduleCoreAudioPickup(deviceName: device.name)
                return
            }
        }

        // Timeout path
        subprocessTask.cancel()
        rowStates[mac] = .failed(until: Date().addingTimeInterval(3))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if case .failed = self?.rowStates[mac] {
                self?.rowStates[mac] = .idle
            }
        }
    }

    private func scheduleCoreAudioPickup(deviceName: String) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        onConnected?(deviceName)
    }
```

Also add a protocol so the fake reconnector unifies with the real one:

```swift
/// Lets tests inject a stub. The real BluetoothReconnector conforms via
/// extension below.
protocol FakeReconnectorProtocol {
    func reconnect(macAddress: String, timeout: TimeInterval) async -> BluetoothReconnector.Result
}

extension FakeReconnector: FakeReconnectorProtocol {}
```

Then change `reconnectorOverride` type to return `FakeReconnectorProtocol`:

```swift
    var reconnectorOverride: ((String) -> FakeReconnectorProtocol)?

    private func makeReconnector(mac: String) -> Any {
        if let make = reconnectorOverride { return make(mac) }
        return BluetoothReconnector()
    }
```

And simplify `runReconnect`'s subprocess kickoff:

```swift
        let subprocessTask = Task.detached(priority: .userInitiated) { () -> BluetoothReconnector.Result in
            if let stub = reconnector as? FakeReconnectorProtocol {
                return await stub.reconnect(macAddress: mac, timeout: 5)
            }
            let real = reconnector as! BluetoothReconnector
            return await real.reconnect(macAddress: mac, timeout: 5)
        }
```

- [ ] **Step 2.5.4: Run tests**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/BluetoothRowStateTests 2>&1 | tail -15
```

Expected: test passes (it asserts `.connecting` mid-flight then `.failed` after stub timeout).

### Task 2.6: Commit Phase 2

- [ ] **Step 2.6.1: Stage and commit production code only**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add Tutti/BluetoothDeviceMonitor.swift Tutti/BluetoothReconnector.swift
git status  # TuttiTests/ should NOT appear (gitignored)
git commit -m "add bluetooth device monitor and reconnector"
```

---

## Phase 3: AudioDeviceManager Hook + UI

### Task 3.1: AudioDeviceManager.handleBluetoothConnected

**Files:**
- Modify: `Tutti/AudioDeviceManager.swift`
- Create: `TuttiTests/AudioDeviceManagerHookTests.swift` (local-only)

- [ ] **Step 3.1.1: Write failing test**

Create `TuttiTests/AudioDeviceManagerHookTests.swift`:

```swift
import XCTest
@testable import Tutti

@MainActor
final class AudioDeviceManagerHookTests: XCTestCase {
    func testHandleConnectedFindsMatchByNormalizedName() {
        // This is a smoke test — it verifies the public API exists and accepts
        // a String. Real integration is covered by the manual test script.
        let manager = AudioDeviceManager()
        manager.handleBluetoothConnected(name: "Nonexistent Test Device")
        // No crash, no assertions about state — just confirms the entrypoint.
        XCTAssertNotNil(manager)
    }
}
```

- [ ] **Step 3.1.2: Run failing test**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/AudioDeviceManagerHookTests 2>&1 | tail -10
```

Expected: compile failure (`handleBluetoothConnected` not defined).

- [ ] **Step 3.1.3: Implement hook and addToSelection helper**

Edit `Tutti/AudioDeviceManager.swift`. Find a sensible location after `refreshDevices()` (around line 276), and add:

```swift
    // MARK: - Bluetooth reconnect hook

    /// Set by BluetoothDeviceMonitor.onConnected on init.
    /// Called when a reconnected device should be merged into selectedIDs.
    func handleBluetoothConnected(name: String) {
        refreshDevices()
        let target = BluetoothMonitorHelpers.normalizeName(name)
        if let match = devices.first(where: {
            BluetoothMonitorHelpers.normalizeName($0.name) == target
        }) {
            addToSelection(match.id)
            return
        }
        // 1.5s wait in BluetoothDeviceMonitor wasn't enough — give Core Audio
        // one more second and try once.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.refreshDevices()
            if let retry = self?.devices.first(where: {
                BluetoothMonitorHelpers.normalizeName($0.name) == target
            }) {
                self?.addToSelection(retry.id)
            }
            // If still no match, give up silently. User will see the device in
            // DevicesCapsule once Core Audio registers it (whenever that is).
        }
    }

    /// Adds a device ID to selectedIDs idempotently and rebuilds the aggregate.
    /// Does NOT change the system default output device.
    private func addToSelection(_ id: AudioDeviceID) {
        guard !selectedIDs.contains(id) else { return }
        selectedIDs.insert(id)
        updateAggregate()
    }
```

(Use `private` if `updateAggregate()` is already private; otherwise match existing visibility.)

- [ ] **Step 3.1.4: Run test to verify it passes**

```bash
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' \
  -only-testing:TuttiTests/AudioDeviceManagerHookTests 2>&1 | tail -10
```

Expected: test passes.

### Task 3.2: Wire BluetoothDeviceMonitor into AppDelegate

**Files:**
- Modify: `Tutti/AppDelegate.swift`

- [ ] **Step 3.2.1: Add the monitor property and wire it in `applicationDidFinishLaunching`**

In `Tutti/AppDelegate.swift`, change the stored properties to add the monitor (above the existing `private let manager = AudioDeviceManager()`):

```swift
    private let manager = AudioDeviceManager()
    private let profiles = ProfileStore()
    private let bluetoothMonitor = BluetoothDeviceMonitor()
    private let popover = TuttiPopover()
```

In `applicationDidFinishLaunching`, after `TrialManager.shared.startTrialIfFirstLaunch()`, insert:

```swift
        // Wire the bluetooth monitor: it pulls system_profiler in the
        // background, and on successful reconnect tells AudioDeviceManager
        // to add the device to the active aggregate.
        bluetoothMonitor.hostedDeviceNames = { [weak manager] in
            Set(manager?.devices.map(\.name) ?? [])
        }
        bluetoothMonitor.onConnected = { [weak manager] name in
            Task { @MainActor in
                manager?.handleBluetoothConnected(name: name)
            }
        }
        Task { @MainActor [bluetoothMonitor] in
            await bluetoothMonitor.warm()
        }
```

Update the `rootView` construction to inject the monitor:

```swift
        let rootView = MenuBarView()
            .environmentObject(manager)
            .environmentObject(profiles)
            .environmentObject(bluetoothMonitor)
            .environment(\.openTuttiSettings, OpenTuttiSettingsAction { [weak self] in
                self?.openSettings()
            })
            .environment(\.tuttiPopover, popover)
```

- [ ] **Step 3.2.2: Build**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

### Task 3.3: BluetoothCapsule + BluetoothRow UI

**Files:**
- Modify: `Tutti/MenuBarView.swift`

- [ ] **Step 3.3.1: Append the capsule and row structs after `ProfilesCapsule`**

In `Tutti/MenuBarView.swift`, find the end of the `ProfilesCapsule` struct (after the closing `}` near line 700 — locate by `grep -n "ProfilesCapsule"`). Append the following structs **before** the `SectionHead` struct (which is around line 713):

```swift
// MARK: - Bluetooth capsule

private struct BluetoothCapsule: View {
    @EnvironmentObject var monitor: BluetoothDeviceMonitor
    @EnvironmentObject var prefs: AppearancePrefs
    @Binding var folded: Bool

    var body: some View {
        let visible = monitor.displayableDevices
        if visible.isEmpty {
            EmptyView()
        } else {
            GlassCapsule {
                VStack(spacing: 0) {
                    SectionHead(title: String(localized: "已配对蓝牙"),
                                trailing: "\(visible.count)",
                                folded: $folded)

                    if !folded {
                        VStack(spacing: 2) {
                            ForEach(visible) { device in
                                BluetoothRow(device: device,
                                             state: monitor.rowStates[device.macAddress] ?? .idle)
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

private struct BluetoothRow: View {
    @EnvironmentObject var monitor: BluetoothDeviceMonitor
    @EnvironmentObject var prefs: AppearancePrefs
    let device: PairedBluetoothDevice
    let state: BluetoothRowState

    private var symbolName: String {
        switch device.minorType {
        case "Headphones", "Headset": return "headphones"
        case "Speakers": return "hifispeaker.fill"
        case "Carkit": return "car.fill"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        Button(action: { Task { await monitor.reconnect(device) } }) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.glassTextHi)
                    .frame(width: 18)
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.glassTextHi)
                Spacer()
                trailingContent
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: innerRowRadius)
                .fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch state {
        case .idle:
            if let lvl = device.batteryLevel {
                Text("\(lvl)%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.glassTextLo)
            }
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(Color.glassTextLo)
        case .connecting:
            Text(String(localized: "连接中..."))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.glassTextLo)
            ProgressView().controlSize(.mini)
        case .failed:
            Text(String(localized: "连接失败"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 3.3.2: Build**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`. Likely errors:
- `'glassTextHi'` not found → look at how `GlassDeviceRow` accesses these colors; mirror the same access pattern.
- `innerRowRadius` not in scope → it's a file-level constant at the top of MenuBarView.swift (line 7), so this should work.

If the GlassDeviceRow uses environment-injected colors, mirror that pattern.

### Task 3.4: Insert BluetoothCapsule into MenuBarView body

**Files:**
- Modify: `Tutti/MenuBarView.swift`

- [ ] **Step 3.4.1: Add the @State + @EnvironmentObject and the capsule placement**

In `struct MenuBarView`, add the EnvironmentObject + folded state near the other state declarations (around line 18):

```swift
    @EnvironmentObject var bluetoothMonitor: BluetoothDeviceMonitor
    @State private var bluetoothFolded = false
```

In `var body: some View`, locate `DevicesCapsule(folded: $devicesFolded)` (line 56) and insert directly after it:

```swift
            DevicesCapsule(folded: $devicesFolded)

            BluetoothCapsule(folded: $bluetoothFolded)

            if showProfiles {
                ProfilesCapsule(...)
                ...
            }
```

- [ ] **Step 3.4.2: Build**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

### Task 3.5: Trigger refresh on popover open

**Files:**
- Modify: `Tutti/AudioDeviceManager.swift` (find the popover visibility callback) or `Tutti/AppDelegate.swift`

- [ ] **Step 3.5.1: Hook bluetoothMonitor.refresh() into popover visibility**

In `AppDelegate.swift`, change the popover visibility closure to also kick a Bluetooth refresh:

```swift
        popover.onVisibilityChange = { [weak manager, bluetoothMonitor] visible in
            manager?.setPopoverVisible(visible)
            if visible {
                Task { @MainActor in
                    await bluetoothMonitor.refresh()
                }
            }
        }
```

- [ ] **Step 3.5.2: Build**

```bash
xcodebuild -project Tutti.xcodeproj -scheme Tutti build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

### Task 3.6: Commit Phase 3

- [ ] **Step 3.6.1: Stage and commit**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add Tutti/AudioDeviceManager.swift Tutti/AppDelegate.swift Tutti/MenuBarView.swift
git status
git commit -m "wire bluetooth monitor into menu bar UI and core audio"
```

---

## Phase 4: Localization (9 languages)

### Task 4.1: Add new xcstrings keys + English sources

**Files:**
- Modify: `Tutti/Localizable.xcstrings`

- [ ] **Step 4.1.1: Open Localizable.xcstrings in Xcode**

```bash
open "/Volumes/990 EP/Dev/tutti/Tutti.xcodeproj"
```

In Xcode's project navigator, open `Localizable.xcstrings`. Click `+` at the bottom-left to add a new key.

- [ ] **Step 4.1.2: Add the four keys**

Add these 4 keys (Chinese source per project convention):

| Key (zh-Hans source) | English (en) |
|---|---|
| `已配对蓝牙` | `Paired Bluetooth` |
| `连接中...` | `Connecting…` |
| `连接失败` | `Failed to connect` |
| `需要蓝牙权限` | `Bluetooth permission required` |

For each key, fill in `en` translation immediately.

- [ ] **Step 4.1.3: Verify keys are referenced by code**

```bash
cd "/Volumes/990 EP/Dev/tutti"
grep -n '已配对蓝牙\|连接中\|连接失败\|需要蓝牙权限' Tutti/MenuBarView.swift Tutti/BluetoothDeviceMonitor.swift 2>&1 | head -10
```

Expected: at least 3 hits (Sections 3.3 + future TCC-denied error UI).

### Task 4.2: Add zh-Hant / ja / ko / fr / de / it / es translations

**Files:**
- Modify: `Tutti/Localizable.xcstrings`

- [ ] **Step 4.2.1: Fill all 7 additional locales**

In Xcode's xcstrings editor, complete each key for all 9 listed languages. Use the table below:

| Key | zh-Hant | ja | ko | fr | de | it | es |
|---|---|---|---|---|---|---|---|
| 已配对蓝牙 | 已配對藍牙 | ペアリング済みBluetooth | 페어링된 블루투스 | Bluetooth jumelé | Gekoppelte Bluetooth-Geräte | Bluetooth abbinato | Bluetooth emparejado |
| 连接中... | 連接中… | 接続中… | 연결 중… | Connexion… | Verbindung… | Connessione… | Conectando… |
| 连接失败 | 連線失敗 | 接続に失敗しました | 연결 실패 | Échec de la connexion | Verbindung fehlgeschlagen | Connessione fallita | Error de conexión |
| 需要蓝牙权限 | 需要藍牙權限 | Bluetoothの権限が必要です | 블루투스 권한이 필요합니다 | Autorisation Bluetooth requise | Bluetooth-Berechtigung erforderlich | Autorizzazione Bluetooth richiesta | Permiso de Bluetooth requerido |

- [ ] **Step 4.2.2: Save xcstrings**

Close and reopen the file in Xcode to confirm saves wrote correctly. Each of the 4 keys should show `9/9 translated`.

### Task 4.3: Commit Phase 4

- [ ] **Step 4.3.1: Stage and commit**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add Tutti/Localizable.xcstrings
git status
git commit -m "translate bluetooth reconnect strings across nine locales"
```

---

## Phase 5: Integration Testing

### Task 5.1: Run the full unit test suite

- [ ] **Step 5.1.1: Run all tests**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodebuild test -project Tutti.xcodeproj -scheme Tutti \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass — the existing license/trial tests (~13) plus the new bluetooth tests (~5).

If any fail, fix before continuing.

### Task 5.2: Manual test script

- [ ] **Step 5.2.1: Build a Debug installable**

```bash
cd "/Volumes/990 EP/Dev/tutti"
xcodebuild -project Tutti.xcodeproj -scheme Tutti -configuration Debug \
  -derivedDataPath build/integ build 2>&1 | tail -5
APP=build/integ/Build/Products/Debug/Tutti.app
```

- [ ] **Step 5.2.2: Reset TCC and launch**

```bash
tccutil reset Bluetooth com.recents.tutti 2>/dev/null || true
killall Tutti 2>/dev/null || true
open "$APP"
```

- [ ] **Step 5.2.3: Walk through the 10-step manual test from the spec**

Reference: `docs/superpowers/specs/2026-05-27-tutti-v031-bluetooth-design.md` → Section "测试 / 手测脚本"

Walk through each numbered step:
1. First-launch discovery: paired Bluetooth list appears in popover
2. First reconnect triggers TCC prompt → allow → 5s reconnect → device joins DevicesCapsule
3. Second reconnect: no TCC prompt
4. Timeout: power off / range out → 5s → red "连接失败" 3s → idle
5. Cancel: `.connecting` re-tap → idle immediately
6. TCC denial path: reset + reject prompt → row shows "需要蓝牙权限"
7. No default-output switch: confirm system default unchanged after reconnect
8. Profile downgrade path: save profile with disconnected device → apply → device not in selection → tap to reconnect → joins
9. App quit cleanup: `ps aux | grep blueutil` after `killall Tutti` — no residue
10. Idempotency: re-tap a `.connecting` row → cancels cleanly

Note any failures with file:line references.

- [ ] **Step 5.2.4: Fix any bugs found**

For each failed manual test, fix the underlying issue. Common likely failures:
- TCC denial UI not implemented (Section 6 of spec mentioned "row shows 需要蓝牙权限"). If not implemented, add a fallback: detect `.failed` with stderr containing "abort signal" → set a special state showing the localization key. Reasonable to defer to v0.3.1.1 if not blocking.
- Battery level not appearing — likely because BluetoothDeviceMonitor doesn't surface it correctly. Check `parsePairedDevices` battery extraction.
- Capsule appears even when displayableDevices is empty (rendering whitespace) — check `EmptyView()` return.

After each fix, re-run the failing manual step.

### Task 5.3: Commit any Phase 5 fixes

- [ ] **Step 5.3.1: Stage and commit fixes (if any)**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git status
git add -p   # interactive
git commit -m "fix bluetooth reconnect integration issues from manual testing"
```

(Skip this commit if no fixes were needed.)

---

## Phase 6: Release Pipeline

### Task 6.1: Bump version

**Files:**
- Modify: `project.yml`

- [ ] **Step 6.1.1: Bump CFBundleShortVersionString and CFBundleVersion**

```bash
cd "/Volumes/990 EP/Dev/tutti"
/usr/bin/sed -i '' \
  -e 's/CFBundleShortVersionString: "0.2.1"/CFBundleShortVersionString: "0.3.1"/' \
  -e 's/CFBundleVersion: "3"/CFBundleVersion: "4"/' \
  project.yml
grep "CFBundleShort\|CFBundleVersion:" project.yml
```

Expected:
```
        CFBundleShortVersionString: "0.3.1"
        CFBundleVersion: "4"
```

- [ ] **Step 6.1.2: Regenerate xcodeproj**

```bash
xcodegen generate
grep "CFBundleShort\|CFBundleVersion" Tutti/Info.plist
```

Expected: 0.3.1 / 4.

### Task 6.2: Update TODO.md (project state tracking)

**Files:**
- Modify: `TODO.md` (gitignored — local only, but tracks progress per project convention)

- [ ] **Step 6.2.1: Edit TODO.md v0.3.x section**

Open `TODO.md`. Change the v0.3.x section header from "全部 park 到 v0.3.1" to "v0.3.1 = 蓝牙重连完成" and add a "已完成代码改动" sub-section listing the work.

(Format: match the existing v0.2.1 / v0.2.0 sections in TODO.md.)

### Task 6.3: Dry-run release.sh end-to-end (without publishing)

- [ ] **Step 6.3.1: Run release.sh with publishing disabled**

Temporarily comment out the `gh release create ...` block (the section starting `echo "==> Publish GitHub release $TAG"`):

```bash
cd "/Volumes/990 EP/Dev/tutti"
# Manually edit scripts/release.sh: comment out the gh release create call
# and the RELEASE_URL=$(...) line that depends on it.
./scripts/release.sh
```

Expected:
- Archive succeeds
- Export succeeds
- `==> Codesign bundled blueutil` step prints success
- `==> Verify signature` deep verify passes
- Notarize accepted
- Staple validate passes
- Build artifact at `build/release/Tutti-0.3.1.zip`

If notarize fails: read log (`xcrun notarytool log <id> --keychain-profile tutti-notary`) and fix.

- [ ] **Step 6.3.2: Run pre-flight verify**

```bash
unzip -o build/release/Tutti-0.3.1.zip -d build/release/extracted
./scripts/verify-bluetooth.sh build/release/extracted/Tutti.app
```

Expected: codesign info shows Developer ID authority. `blueutil --paired` either succeeds (if your account already authorized Tutti) or shows the abort-signal message (which is expected — the install-and-prompt flow lives in the app itself).

- [ ] **Step 6.3.3: Restore release.sh to normal**

Un-comment the `gh release create` block. Verify:

```bash
cd "/Volumes/990 EP/Dev/tutti"
git diff scripts/release.sh | head -20
```

Should show only the Task 1.4 codesign block as the diff vs. main.

### Task 6.4: Final acceptance install

- [ ] **Step 6.4.1: Install the release artifact and run the full manual test cycle**

```bash
cd "/Volumes/990 EP/Dev/tutti"
killall Tutti 2>/dev/null || true
rm -rf /Applications/Tutti.app
cp -R build/release/extracted/Tutti.app /Applications/Tutti.app
tccutil reset Bluetooth com.recents.tutti
open /Applications/Tutti.app
```

Re-run manual test steps 1-10 from Phase 5 against the **release-signed** build. The TCC prompt should specifically say "Tutti 想要使用蓝牙" with the configured usage description text.

### Task 6.5: Commit Phase 6

- [ ] **Step 6.5.1: Stage version bump**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git add project.yml Tutti.xcodeproj Tutti/Info.plist
git status
git commit -m "bump version to 0.3.1 for bluetooth reconnect release"
```

### Task 6.6: Publish release

- [ ] **Step 6.6.1: Run release.sh in real publish mode**

```bash
cd "/Volumes/990 EP/Dev/tutti"
git push origin main   # push commits first
./scripts/release.sh
```

This will create tag `v0.3.1`, push artifacts to GitHub Releases.

- [ ] **Step 6.6.2: Verify release URL**

The script prints the release URL on completion. Open it in a browser to confirm.

---

## Self-Review (writing-plans skill checklist)

**Spec coverage**: every numbered spec section has at least one task:
- "Context" → covered by Phase 1 spike rationale
- "Lockedin decisions" → reflected in implementation (Free, no default-output switch, etc.)
- "Architecture" → Tasks 2.1-2.5, 3.1-3.5
- "File list" → File Structure section above
- "Data models" → Task 2.2
- "Discovery flow" → Task 2.3-2.4
- "Reconnect flow" → Task 2.5
- "UI design" → Task 3.3-3.4
- "Bundling + signing" → Task 1.1-1.5, 6.3-6.6
- "Error handling + edge cases" → Task 2.5 (cancel/timeout), 5.2 (manual test)
- "Testing" → Tasks 2.1, 2.3, 2.5, 3.1, 5.1, 5.2
- "Risks" → Phase 1 gate addresses the highest-probability risk

**Placeholder scan**: no TBD/TODO/placeholder language. All code blocks are complete.

**Type consistency**: `PairedBluetoothDevice`, `BluetoothRowState`, `BluetoothReconnector.Result`, `BluetoothMonitorHelpers.normalizeName` used consistently across tasks. `onConnected` callback shape (`((String) -> Void)?`) consistent in 2.4, 3.1, 3.2.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-27-tutti-v031-bluetooth-reconnect.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
