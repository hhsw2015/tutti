<p align="center">
  <img src="docs/screenshots/icon.png" alt="Tutti app icon" width="128" height="128">
</p>

<h1 align="center">Tutti</h1>

<p align="center"><em>One sound, every speaker.</em></p>

<p align="center">A macOS menu bar utility that plays the same audio through any number of output devices at once.</p>

<p align="center"><a href="README.zh.md">中文版 README</a></p>

<!-- TODO screenshots:
  docs/screenshots/menubar.png  - menu bar icon, three states stacked (idle / playing / muted)
  docs/screenshots/popover.png  - popover open with 2+ devices selected, sliders visible
  docs/screenshots/settings.png - Settings -> License tab in activated state (scallop badge + key)
-->

## Features

- **Multi-device output**: tick multiple outputs in the menu bar; Tutti creates an Aggregate Device on the fly and sets it as the system default.
- **Single-device passthrough**: pick just one and Tutti switches the system default directly, no virtual device created.
- **Master and per-device volume**: one slider for everything, individual sliders for each output.
- **Master and per-device mute**: silence one speaker while the rest keep playing.
- **Three-state status**: "playing on all", "partially muted", or "all muted", with synchronized text and color dot.
- **Hardware volume key takeover** (Pro): keyboard volume up, down, and mute keys drive the aggregate output globally. Shift+Option fine-grain steps match the system. Requires Accessibility permission.
- **Bluetooth headphone battery**: shown next to the device name when available.
- **External change awareness**: switching the default output via System Settings or Control Center auto-destroys the Aggregate Device and updates the selection.
- **Orphan device cleanup**: cleans up Aggregate Devices left behind from a previous crash, plus legacy MultiOut residues, on launch.
- **Light / Dark / System** theme.
- **Launch at login** and **GitHub Releases auto-update check**.

## Use cases

- **Shared listening**: living room speaker plus Bluetooth headphones at the same time; your friend wears headphones while you play out loud.
- **Streaming, presenting, lecture recording**: monitor through headphones while broadcasting to an audience or a capture card.
- **Multi-room playback**: drive a pair of wired speakers in the living room and another in the bedroom from one Mac.
- **Collaborative monitoring**: share one Mac with two pairs of headphones plugged in.
- **Teaching**: teacher hears prompts in their headphones while the classroom speaker plays for students.

## Tutti Pro

Every new install gets a **7-day Pro trial** on first launch, no license key required. After the trial, all free-tier features keep working without limits.

Pro unlocks one power-user convenience: **hardware volume key takeover**. Your Mac's keyboard volume keys drive the aggregate output directly, so you stop dragging sliders to balance multiple devices.

- **$7.99 one-time**, no subscription.
- **Up to 2 Macs** per license. Activate and deactivate from Settings -> License.
- **All future Pro features included** at no extra cost.

[Get a Tutti Pro license](https://tutti.recents.com/buy)

## Localization

Localized in 9 languages: Simplified Chinese, Traditional Chinese, English, Japanese, Korean, French, German, Italian, Spanish.

## Requirements

- macOS 13.0 or later
- Accessibility permission, only when you use the Pro hardware volume key takeover

## Build

```bash
brew install xcodegen
cd tutti
xcodegen generate
xcodebuild -project Tutti.xcodeproj -scheme Tutti build
```

## License

Tutti ships under a Source-Available model rather than traditional Open Source, licensed under [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0).

Anyone can download, compile, and use Tutti for personal, non-commercial purposes free of charge.

> **For developers**: you're welcome to clone this repo and build it yourself. Per the PolyForm license, you may not use this code or any modified version for commercial gain, including shipping it on an app store or bundling it into a paid service.
