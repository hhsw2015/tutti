# Tutti

macOS menu bar utility that plays the same audio through any number of output devices at once. Swift + SwiftUI, `LSUIElement` agent app (no dock icon).

## Stack

- **Language / UI**: Swift 5.9, SwiftUI (AppKit only where SwiftUI can't reach — status item, panels, OSD).
- **Deployment target**: macOS 13.0. Don't raise without asking.
- **Dependencies**: Sparkle (auto-update) via SPM. No other third-party deps — use Apple frameworks first (CoreAudio, IOBluetooth, AVFoundation).

## Build

`project.yml` is the source of truth for project config (version, bundle id, signing, Sparkle keys, localizations). `Tutti.xcodeproj` is generated from it by [XcodeGen] but is committed. After editing `project.yml`, regenerate before building:

```
xcodegen generate
xcodebuild -scheme Tutti -configuration Debug build
```

Edit build settings, version, or Sparkle config in `project.yml`, never directly in the `.xcodeproj`.

## Release

```
./scripts/release.sh           # release current version in project.yml
./scripts/release.sh 0.2.4     # bump version first, then release
```

Full pipeline: bump → `xcodegen generate` → archive → Developer ID sign → notarize → staple → EdDSA-sign zip → update `docs/appcast.xml` → publish GitHub Release → commit & push appcast.

- Notary credential lives in the keychain profile `tutti-notary` (set up once via `xcrun notarytool store-credentials`); it is not in the repo.
- `CFBundleVersion` is a monotonic integer that Sparkle compares to decide update order — release.sh auto-increments it; don't reuse the marketing string for it.
- Release notes go in `docs/release-notes/`; `scripts/inject-localized-notes.py` injects per-language `<description>` elements into the appcast for Sparkle's update alert.

## Conventions

- **`TODO.md` is the single source of truth** for the roadmap, progress, and pending decisions. Read it first; record new tasks and status there, not scattered across commits.
- **Localization**: all user-facing strings live in `Tutti/Localizable.xcstrings` (String Catalog). Ships 9 locales (zh-Hans, zh-Hant, en, ja, ko, fr, de, it, es); development region is zh-Hans. Any new string needs at least zh-Hans + en in the same change.
- **GitHub-facing text** (README, Release body) is English only. In-app update notes are localized.

## Map

- `AudioDeviceManager.swift` (~680 lines) — CoreAudio: enumerates devices, builds/tears down the Aggregate Device, sets the system default, master/per-device volume + mute. The core engine; keep its public surface stable.
- `MenuBarView.swift` (~1090 lines) — the popover UI: device list, sliders, three-state status. Largest file; split only when a boundary is already clear, don't refactor opportunistically.
- `SettingsView.swift` (~950 lines) — settings + License tab.
- `LicenseManager.swift` / `TrialManager.swift` / `ProfileStore.swift` — Pro activation (Dodo Payments license keys), trial state, saved presets.
- `UpdateChecker.swift` / `AppDelegate.swift` — Sparkle integration; AppDelegate also centers windows and keeps Sparkle update windows on the active display.
- `VolumeKeyMonitor.swift` / `VolumeOSDController.swift` — Pro volume-takeover (keyboard/scroll → aggregate output) and the replacement OSD.
- `scripts/airplay-spike.swift` — throwaway exploration spike, not shipped. Don't treat as production code.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
