import SwiftUI
import CoreAudio
import ServiceManagement

struct MenuBarView: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var presets: PresetStore
    @State private var showSaveField = false
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("设备")

            ForEach(manager.devices) { device in
                DeviceRow(device: device)
                    .environmentObject(manager)
            }

            if manager.devices.isEmpty {
                Text("未发现音频输出设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if !presets.presets.isEmpty {
                divider()
                sectionHeader("预设")
                ForEach(presets.presets) { preset in
                    PresetRow(preset: preset)
                        .environmentObject(manager)
                        .environmentObject(presets)
                }
            }

            divider()

            Toggle(isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enabled in
                    try? enabled ? SMAppService.mainApp.register()
                                 : SMAppService.mainApp.unregister()
                }
            )) {
                Text("开机自动启动")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            divider()

            if showSaveField {
                saveField
            }

            bottomBar
        }
        .frame(width: 300)
        .padding(.vertical, 8)
    }

    private var saveField: some View {
        HStack(spacing: 6) {
            TextField("预设名称", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            Button("保存") {
                if !presetName.isEmpty {
                    let uids = manager.devices
                        .filter { manager.selectedIDs.contains($0.id) }
                        .map { $0.uid }
                    presets.add(name: presetName, uids: uids)
                    presetName = ""
                    showSaveField = false
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("取消") {
                presetName = ""
                showSaveField = false
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var bottomBar: some View {
        HStack {
            Button(showSaveField ? "取消保存" : "保存当前预设") {
                if showSaveField {
                    showSaveField = false
                    presetName = ""
                } else {
                    showSaveField = true
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(manager.selectedIDs.count >= 2 ? .blue : .secondary)
            .disabled(manager.selectedIDs.count < 2)

            Spacer()

            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func divider() -> some View {
        Divider().padding(.vertical, 4)
    }
}

struct DeviceRow: View {
    let device: AudioDevice
    @EnvironmentObject var manager: AudioDeviceManager

    var isSelected: Bool { manager.selectedIDs.contains(device.id) }

    var volume: Binding<Float> {
        Binding(
            get: { manager.volumes[device.id] ?? 1.0 },
            set: { manager.setVolume($0, for: device.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { manager.toggle(device) } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 16)
                    Image(systemName: device.symbolName)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 14)
                    Text(device.name)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            if isSelected {
                if device.canSetVolume {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                            .frame(width: 14, alignment: .center)
                        Slider(value: volume, in: 0...1)
                        Text(String(format: "%d%%", Int(volume.wrappedValue * 100)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.leading, 52)
                    .padding(.trailing, 12)
                    .padding(.bottom, 5)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("当前设备不支持音量调节")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 52)
                    .padding(.bottom, 5)
                }
            }
        }
    }
}

struct PresetRow: View {
    let preset: Preset
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var presets: PresetStore

    var body: some View {
        HStack {
            Button {
                manager.applyPreset(uids: preset.deviceUIDs)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 16)
                    Text(preset.name)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            Button { presets.delete(preset) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
    }
}
