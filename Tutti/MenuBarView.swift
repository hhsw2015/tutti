import SwiftUI
import CoreAudio

private let panelWidth: CGFloat = 320
private let capsuleRadius: CGFloat = 22
private let innerRowRadius: CGFloat = 14
private let capsuleGap: CGFloat = 8

// MARK: - Root

struct MenuBarView: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @StateObject private var updater = UpdateChecker()
    @StateObject private var prefs = AppearancePrefs.shared
    @State private var showingSettings = false
    @State private var devicesFolded = false

    private var showMaster: Bool { manager.selectedIDs.count >= 2 }

    var body: some View {
        ZStack {
            Group {
                if showingSettings {
                    SettingsView(visible: $showingSettings, updater: updater)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    mainView
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: showingSettings)
        }
        .frame(width: panelWidth)
        .background(TransparentWindow(theme: prefs.theme))
        .environmentObject(prefs)
        .preferredColorScheme(prefs.theme.colorScheme)
    }

    private var mainView: some View {
        VStack(spacing: capsuleGap) {
            StatusCapsule()

            if showMaster {
                MasterCapsule()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            DevicesCapsule(folded: $devicesFolded)

            DockCapsule(showingSettings: $showingSettings, updater: updater)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .animation(.easeOut(duration: 0.20), value: showMaster)
        .animation(.easeOut(duration: 0.20), value: devicesFolded)
    }
}

// MARK: - Status capsule

private struct StatusCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager

    private var count: Int { manager.selectedIDs.count }
    private var isMuted: Bool { manager.isMuted }

    private var statusText: String {
        if isMuted { return "已静音 · \(count) 个设备待命" }
        switch count {
        case 0:  return "待机"
        case 1:  return "正在输出"
        default: return "正在输出 · \(count) 个设备"
        }
    }

    private var dotColor: Color {
        if isMuted { return .muteRed }
        if count > 0 { return .statusGreen }
        return Color.primary.opacity(0.25)
    }

    var body: some View {
        GlassCapsule(cornerRadius: 18) {
            HStack(spacing: 8) {
                StatusDot(color: dotColor, active: count > 0 || isMuted)
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.glassTextHi)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("TUTTI")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.glassTextLo)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Master capsule

private struct MasterCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var prefs: AppearancePrefs

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { manager.masterVolume },
            set: { manager.setMasterVolume($0) }
        )
    }

    var body: some View {
        let muted = manager.isMuted
        GlassCapsule(tint: muted ? .muteRed : nil) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(muted ? "总音量 · 已静音" : "总音量")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(muted ? Color.muteRed : Color.glassTextHi)
                    Spacer()
                    Text("\(Int(manager.masterVolume * 100))%")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Color.glassTextMid)
                }

                HStack(spacing: 10) {
                    MuteButton(muted: muted) { manager.toggleMasterMute() }
                    GlassSlider(value: volumeBinding,
                                accent: prefs.accentColor,
                                muted: muted)
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

private struct MuteButton: View {
    let muted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: muted
                                ? [Color(red: 1.0, green: 0.48, blue: 0.45),
                                   Color(red: 1.0, green: 0.27, blue: 0.23)]
                                : [Color.primary.opacity(0.22),
                                   Color.primary.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.glassInnerStroke, lineWidth: 0.5)
                    )
                    .frame(width: 32, height: 32)
                    .shadow(color: muted ? Color.muteRed.opacity(0.35) : .clear,
                            radius: 6, y: 1)

                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted ? Color.white : Color.glassTextHi)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass slider

private struct GlassSlider: View {
    @Binding var value: Float
    var accent: Color
    var muted: Bool = false
    var trackHeight: CGFloat = 6
    var knobSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillWidth = max(0, min(1, CGFloat(value))) * w

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .overlay(
                        Capsule().stroke(Color.glassBorder, lineWidth: 0.5)
                    )
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: muted
                                ? [Color.primary.opacity(0.40), Color.primary.opacity(0.20)]
                                : [accent.opacity(0.95).lighter(by: 0.25), accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: fillWidth, height: trackHeight)
                    .shadow(color: muted ? .clear : accent.opacity(0.55),
                            radius: 4, y: 0)

                Circle()
                    .fill(
                        RadialGradient(colors: [.white, Color(white: 0.94)],
                                       center: .init(x: 0.35, y: 0.30),
                                       startRadius: 0, endRadius: knobSize)
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.5))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: fillWidth - knobSize / 2)
            }
            .frame(height: max(trackHeight, knobSize))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = max(0, min(1, g.location.x / w))
                        value = Float(v)
                    }
            )
        }
    }
}

// MARK: - Devices capsule

private struct DevicesCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var prefs: AppearancePrefs
    @Binding var folded: Bool

    var body: some View {
        GlassCapsule {
            VStack(spacing: 0) {
                SectionHead(
                    title: "输出设备",
                    trailing: "\(manager.selectedIDs.count) / \(manager.devices.count) 已选",
                    folded: $folded
                )

                if !folded {
                    VStack(spacing: 2) {
                        if manager.devices.isEmpty {
                            Text("未发现音频输出设备")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.glassTextLo)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                        } else {
                            ForEach(manager.devices) { device in
                                GlassDeviceRow(
                                    device: device,
                                    isSelected: manager.selectedIDs.contains(device.id)
                                )
                            }
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

struct AccentPillButton: ButtonStyle {
    @EnvironmentObject var prefs: AppearancePrefs

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [
                            prefs.accentColor.lighter(by: 0.20),
                            prefs.accentColor
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Section head (chevron + label + trailing)

private struct SectionHead<Trailing: View>: View {
    let title: String
    @Binding var folded: Bool
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Button { withAnimation { folded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(folded ? -90 : 0))
                        .foregroundStyle(Color.glassTextLo)
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.glassTextLo)
                        .textCase(.uppercase)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

extension SectionHead where Trailing == TrailingLabel {
    init(title: String, trailing: String, folded: Binding<Bool>) {
        self.init(title: title, folded: folded) {
            TrailingLabel(text: trailing)
        }
    }
}

private struct TrailingLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.glassTextLo)
    }
}

// MARK: - Device row

private struct GlassDeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var prefs: AppearancePrefs
    @State private var hovering = false

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { manager.volumes[device.id] ?? 1.0 },
            set: { manager.setVolume($0, for: device.id) }
        )
    }

    private var battery: Int? { manager.batteryLevels[device.id] }
    private var lowBattery: Bool { (battery ?? 100) < 20 }

    private var muted: Bool { manager.isMuted(device.id) }

    private var canMute: Bool { isSelected && device.canSetVolume }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button {
                    if canMute {
                        manager.toggleMute(deviceID: device.id)
                    } else {
                        manager.toggle(device)
                    }
                } label: {
                    GlassIconBadge(
                        symbol: muted ? "speaker.slash.fill" : device.symbolName,
                        selected: isSelected,
                        muted: muted,
                        accent: prefs.accentColor
                    )
                }
                .buttonStyle(.plain)
                .help(canMute ? (muted ? "取消静音" : "静音此设备") : "")

                Button { manager.toggle(device) } label: {
                    HStack(spacing: 11) {
                        Text(device.name)
                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(Color.glassTextHi)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let bat = battery {
                            BatteryPill(percent: bat, low: lowBattery)
                        }

                        if !device.canSetVolume {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.glassTextDim)
                        } else if isSelected {
                            CheckBadge(color: prefs.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: innerRowRadius, style: .continuous))
            .onHover { hovering = $0 }

            if isSelected && device.canSetVolume {
                HStack(spacing: 8) {
                    GlassSlider(value: volumeBinding,
                                accent: prefs.accentColor,
                                trackHeight: 4,
                                knobSize: 11)
                        .frame(height: 12)
                    Text("\(Int(volumeBinding.wrappedValue * 100))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color.glassTextMid)
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .padding(.leading, 51)
                .padding(.trailing, 12)
                .padding(.top, 2)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            prefs.accentColor.opacity(0.18)
        } else if hovering {
            Color.glassHoverBg
        } else {
            Color.clear
        }
    }
}

// MARK: - Glass icon badge

private struct GlassIconBadge: View {
    let symbol: String
    let selected: Bool
    var muted: Bool = false
    let accent: Color

    private var fill: Color {
        if muted { return .muteRed }
        if selected { return accent }
        return Color.primary.opacity(0.10)
    }

    private var symbolColor: Color {
        (muted || selected) ? .white : .glassTextHi
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 30, height: 30)

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(symbolColor)
        }
    }
}

private struct CheckBadge: View {
    let color: Color

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white, color)
    }
}

private struct BatteryPill: View {
    let percent: Int
    let low: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 9))
            Text("\(percent)")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(low ? Color.muteRed : Color.glassTextMid)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(low ? Color.muteRed.opacity(0.22) : Color.glassInnerFill)
        )
        .overlay(
            Capsule().stroke(low ? Color.muteRed.opacity(0.35) : Color.glassInnerStroke, lineWidth: 0.5)
        )
        .shadow(color: low ? Color.muteRed.opacity(0.30) : .clear, radius: 5, y: 0)
    }

    private var iconName: String {
        switch percent {
        case 75...:     return "battery.100"
        case 50..<75:   return "battery.75"
        case 25..<50:   return "battery.50"
        case 10..<25:   return "battery.25"
        default:        return "battery.0"
        }
    }
}

// MARK: - Dock-style action capsule

private struct DockCapsule: View {
    @EnvironmentObject var prefs: AppearancePrefs
    @Binding var showingSettings: Bool
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        GlassCapsule(cornerRadius: 18) {
            HStack(spacing: 6) {
                DockButton(symbol: "gearshape", title: "设置", weight: .medium) {
                    withAnimation { showingSettings = true }
                } trailing: {
                    if updater.hasUpdate {
                        Circle().fill(prefs.accentColor).frame(width: 5, height: 5)
                    }
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.20))
                    .frame(width: 1, height: 14)

                DockButton(symbol: "power", title: "退出", weight: .semibold) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(6)
        }
    }
}

private struct DockButton<Trailing: View>: View {
    let symbol: String
    let title: String
    let weight: Font.Weight
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(symbol: String,
         title: String,
         weight: Font.Weight,
         action: @escaping () -> Void,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.weight = weight
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: weight))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                trailing()
            }
            .foregroundStyle(Color.glassTextHi)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
