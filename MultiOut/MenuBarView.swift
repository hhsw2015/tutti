import SwiftUI
import CoreAudio

struct MenuBarView: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var presets: PresetStore
    @StateObject private var updater = UpdateChecker()
    @State private var showSaveField = false
    @State private var presetName = ""
    @State private var showingSettings = false

    private var showPresetsSection: Bool {
        !presets.presets.isEmpty || manager.selectedIDs.count >= 2
    }

    var body: some View {
        if showingSettings {
            SettingsView(visible: $showingSettings, updater: updater)
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            statusHeader
            hairlineDivider()

            VStack(spacing: 0) {
                if manager.devices.isEmpty {
                    Text("未发现音频输出设备")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textLo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ForEach(manager.devices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: manager.selectedIDs.contains(device.id)
                        )
                        .animation(.easeOut(duration: 0.16),
                                   value: manager.selectedIDs.contains(device.id))
                    }
                }
            }
            .padding(.vertical, 4)

            if showPresetsSection {
                hairlineDivider()
                presetsSection
            }

            if showSaveField {
                hairlineDivider()
                saveField
            }

            hairlineDivider()
            footer
        }
        .frame(width: 320)
        .background(Color.chassis)
    }

    private var statusHeader: some View {
        HStack(spacing: 9) {
            ZStack {
                if manager.isActive {
                    Circle()
                        .fill(Color.signal.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .blur(radius: 3.5)
                }
                Circle()
                    .fill(manager.isActive ? Color.signal : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            .frame(width: 16, height: 16)

            Text(manager.isActive
                 ? "正在输出 · \(manager.selectedIDs.count) 个设备"
                 : "待机")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(manager.isActive ? Color.textHi : Color.textMid)

            Spacer()

            Text("MULTIOUT")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.textLo)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var presetsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预设")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.textLo)
                Spacer()
                if manager.selectedIDs.count >= 2 {
                    Button {
                        showSaveField.toggle()
                        if !showSaveField { presetName = "" }
                    } label: {
                        Text(showSaveField ? "取消" : "+ 保存当前")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(showSaveField ? Color.textMid : Color.armed)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, presets.presets.isEmpty ? 10 : 4)

            if !presets.presets.isEmpty {
                VStack(spacing: 0) {
                    ForEach(presets.presets) { preset in
                        PresetRow(preset: preset)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var saveField: some View {
        HStack(spacing: 7) {
            TextField("预设名称", text: $presetName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.textHi)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
                        )
                )
                .onSubmit { commitSave() }

            Button("保存") { commitSave() }
                .buttonStyle(ArmedButton())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func commitSave() {
        guard !presetName.isEmpty else { return }
        let uids = manager.devices
            .filter { manager.selectedIDs.contains($0.id) }
            .map { $0.uid }
        presets.add(name: presetName, uids: uids)
        presetName = ""
        showSaveField = false
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { showingSettings = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                    Text("设置")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.3)
                    if updater.hasUpdate {
                        Circle().fill(Color.armed).frame(width: 5, height: 5)
                    }
                }
                .foregroundStyle(Color.textMid)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("退出")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.3)
                }
                .foregroundStyle(Color.textMid)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

struct DeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool
    @EnvironmentObject var manager: AudioDeviceManager
    @State private var hovering = false

    private var volume: Binding<Float> {
        Binding(
            get: { manager.volumes[device.id] ?? 1.0 },
            set: { manager.setVolume($0, for: device.id) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isSelected ? Color.armed : Color.clear)
                .frame(width: 2.5)

            VStack(alignment: .leading, spacing: 0) {
                Button { manager.toggle(device) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: device.symbolName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.armed : Color.textMid)
                            .frame(width: 18, alignment: .center)

                        Text(device.name)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Color.textHi : Color.textMid)
                            .lineLimit(1)

                        if let rate = manager.sampleRates[device.id], rate > 0 {
                            Text(formatSampleRate(rate))
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .tracking(0.3)
                                .foregroundStyle(Color.textLo)
                        }

                        Spacer(minLength: 6)

                        if isSelected {
                            HStack(spacing: 1) {
                                Text("\(Int(volume.wrappedValue * 100))")
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color.textHi)
                                Text("%")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.textLo)
                                    .padding(.leading, 1)
                            }
                        }
                    }
                    .padding(.leading, 11)
                    .padding(.trailing, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSelected {
                    if device.canSetVolume {
                        LEDMeter(value: volume)
                            .padding(.leading, 41)
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                            .padding(.top, 1)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                            Text("此设备不支持音量调节")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.textLo)
                        .padding(.leading, 41)
                        .padding(.bottom, 9)
                        .padding(.top, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .background(rowBackground)
        .onHover { hovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.armed.opacity(0.07) }
        if hovering { return Color.white.opacity(0.04) }
        return Color.clear
    }
}

private func formatSampleRate(_ hz: Double) -> String {
    let k = hz / 1000
    if k.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(k))k"
    }
    return String(format: "%.1fk", k)
}

struct PresetRow: View {
    let preset: Preset
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var presets: PresetStore
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                manager.applyPreset(uids: preset.deviceUIDs)
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textLo)
                        .frame(width: 18, alignment: .center)
                    Text(preset.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMid)
                        .lineLimit(1)
                    Spacer()
                    Text("\(preset.deviceUIDs.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textLo)
                        .padding(.trailing, hovering ? 22 : 0)
                }
                .padding(.leading, 13.5)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hovering {
                Button {
                    presets.delete(preset)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.danger.opacity(0.9))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
        .background(hovering ? Color.white.opacity(0.04) : Color.clear)
        .onHover { hovering = $0 }
    }
}

struct LEDMeter: View {
    @Binding var value: Float
    var segments: Int = 22

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(0..<segments, id: \.self) { i in
                    let frac = Float(i + 1) / Float(segments)
                    let isOn = value >= frac * 0.96
                    Rectangle()
                        .fill(color(for: frac, on: isOn))
                        .frame(maxWidth: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = max(0, min(1, g.location.x / geo.size.width))
                        value = Float(v)
                    }
            )
        }
        .frame(height: 6)
    }

    private func color(for frac: Float, on: Bool) -> Color {
        if !on { return Color.white.opacity(0.05) }
        if frac > 0.88 { return Color.danger }
        if frac > 0.72 { return Color.armed }
        return Color.armed.opacity(0.9)
    }
}

struct ArmedButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.chassis)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.armedDim : Color.armed)
            )
    }
}
