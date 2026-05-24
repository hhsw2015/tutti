<p align="center">
  <img src="docs/screenshots/icon.png" alt="Tutti app icon" width="128" height="128">
</p>

<h1 align="center">Tutti</h1>

<p align="center"><em>One sound, every speaker.</em></p>

<p align="center">A macOS menu bar utility that plays the same audio through any number of output devices at once.</p>

<p align="center"><a href="README.zh.md">中文版 README</a></p>

## Features

- **Multi-device output** — Tick multiple outputs in the menu bar; Tutti creates an Aggregate Device on the fly and sets it as the system default
- **Single-device passthrough** — Pick just one and Tutti switches the system default directly, no virtual device created
- **Master / per-device volume** — One slider for everything, individual sliders for each output
- **Master / per-device mute** — Mute one speaker while the rest keep playing
- **Three-state status indicator** — Playing on all / partially muted / all muted, with synchronized text and color dot
- **Hardware volume key takeover** — Aggregate devices break the system volume keys; Tutti uses CGEventTap to intercept volume up/down/mute globally and forwards them to each sub-device. Shift+Option fine-grain steps match the system (requires Accessibility permission)
- **Bluetooth headphone battery** — Reads paired Bluetooth output battery via `system_profiler SPBluetoothDataType`
- **External change awareness** — Switching the default output via System Settings or Control Center auto-destroys the Aggregate Device and updates the selection
- **Orphan device cleanup** — Cleans up Aggregate Devices left behind from a previous crash (and legacy MultiOut residues) on launch
- **Light / Dark / System** theme
- **Launch at login** + **GitHub Releases auto-update check**

## Use cases

- **Shared listening** — Living room speaker + Bluetooth headphones at the same time; your friend wears headphones while you play out loud
- **Streaming / presenting / lecture recording** — Monitor through headphones while broadcasting to an audience or a capture card
- **Multi-room playback** — Drive two pairs of wired speakers (e.g. living room + bedroom) — a poor man's AirPlay multi-room
- **Collaborative monitoring** — Share one Mac with two pairs of headphones plugged in
- **Teaching** — Teacher hears prompts in their headphones while the classroom speaker plays for students

## Highlights

- Pure native Swift + SwiftUI + CoreAudio, zero third-party dependencies
- LSUIElement menu-bar-only app, no Dock icon
- Hand-drawn Broadcast Dot menu bar icon with three-state visualization (idle / playing / muted)
- Chinese-first UI; UX copy is specifically designed to honestly convey the partial-mute state
- Aggregate devices are cleaned up on quit, crash, or system default-output change — your audio environment is never polluted

## Requirements

- macOS 13.0+
- Accessibility permission on first launch (for hardware volume key takeover)

## Build

```bash
brew install xcodegen
cd tutti
xcodegen generate
xcodebuild -project Tutti.xcodeproj -scheme Tutti build
```

## License & Pricing

Tutti ships under a **Source-Available** model rather than traditional Open Source. The goal is to keep the code transparent and share CoreAudio practice with the community, while keeping the project sustainable.

This project is licensed under [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0).

### Free tier (personal, non-commercial)

Anyone can download, compile, and use Tutti for **personal, non-commercial** purposes free of charge.

The free tier is fully functional with no device-count cap — connect as many speakers, headphones and AirPods as your Mac supports. Multi-device output, per-device sliders, mute-on-tap, theme switching, Bluetooth battery readout, auto-launch and update checks are all included.

### Tutti Pro — $7.99 one-time

Pro unlocks a single power-user convenience: **hardware volume key takeover**. Your Mac's keyboard volume keys (and the volume keys on supported keyboards) drive the aggregate output directly — no more dragging sliders to balance multiple devices.

Every new Tutti install gets a **7-day Pro trial** on first launch, no license key required. After it ends, all free-tier features keep working unchanged.

[Get a Tutti Pro license](https://tutti.recents.com/buy) — $7.99 one-time, lifetime activation, up to 2 Macs per license. **All future Pro features are included** at no extra cost.

> **A note for developers**: You're welcome to clone this repo and build it yourself. Per the PolyForm license, however, you may not use this code or any modified version for commercial gain (e.g. shipping it on an app store, or bundling it into a paid service).
