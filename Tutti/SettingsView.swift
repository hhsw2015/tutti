import SwiftUI
import ApplicationServices
import ServiceManagement

struct SettingsView: View {
    @Binding var visible: Bool
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        VStack(spacing: 8) {
            header

            SettingsCapsule(title: "主题") {
                ThemePicker()
            }

            SettingsCapsule(title: "权限") {
                PermissionRow()
            }

            SettingsCapsule(title: "启动") {
                AutoLaunchRow()
            }

            SettingsCapsule(title: "更新") {
                UpdatesSection(updater: updater)
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation { visible = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("设置")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.glassTextHi)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("TUTTI")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(Color.glassTextLo)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Text("v\(updater.currentVersion)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.glassTextLo)
            Spacer()
            Text("One sound, every speaker")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.glassTextLo)
        }
        .padding(.horizontal, 4)
    }
}

private struct SettingsCapsule<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassCapsule {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.glassTextLo)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                content()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThemePicker: View {
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ThemeChoice.allCases.enumerated()), id: \.element) { idx, choice in
                let selected = prefs.theme == choice
                let prevSelected = idx > 0 && prefs.theme == ThemeChoice.allCases[idx - 1]

                ThemeSegment(
                    label: choice.label,
                    symbol: choice.symbol,
                    selected: selected,
                    accent: prefs.accentColor
                ) {
                    prefs.theme = choice
                }
                .overlay(alignment: .leading) {
                    if idx > 0 && !selected && !prevSelected {
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1, height: 14)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }
}

private struct ThemeSegment: View {
    let label: String
    let symbol: String
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.glassTextHi)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? accent : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PermissionRow: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        let granted = manager.hasAccessibilityPermission
        HStack(spacing: 9) {
            StatusDot(color: granted ? .statusGreen : .muteRed)

            Text(granted ? "辅助功能已授权" : "辅助功能未授权")
                .font(.system(size: 12))
                .foregroundStyle(Color.glassTextHi)

            Spacer()

            if !granted {
                Button { openAccessibilitySettings() } label: {
                    Text("去授权")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(prefs.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AutoLaunchRow: View {
    @State private var enabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        AccentCheckboxRow(title: "开机自动启动", isOn: enabled, toggle: toggle)
    }

    private func toggle() {
        if enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

private struct AccentCheckboxRow: View {
    let title: String
    let isOn: Bool
    let toggle: () -> Void
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.glassInnerStroke, lineWidth: 0.8)
                        .frame(width: 15, height: 15)
                    if isOn {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(prefs.accentColor)
                            .frame(width: 15, height: 15)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.glassTextHi)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct UpdatesSection: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccentCheckboxRow(
                title: "启动时自动检查更新",
                isOn: updater.autoCheckEnabled
            ) { updater.autoCheckEnabled.toggle() }

            HStack(spacing: 8) {
                Button {
                    Task { await updater.check() }
                } label: {
                    Text(isChecking ? "检查中…" : "检查更新")
                }
                .buttonStyle(AccentPillButton())
                .disabled(isChecking)

                statusView
                    .font(.system(size: 11))
                    .foregroundStyle(Color.glassTextMid)

                Spacer()
            }
        }
    }

    private var isChecking: Bool {
        updater.status == .checking
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.status {
        case .idle, .checking:
            EmptyView()
        case .upToDate:
            Text("已是最新版本").foregroundStyle(Color.glassTextMid)
        case .updateAvailable(let version, let url):
            HStack(spacing: 5) {
                Text("新版本 \(version)")
                    .foregroundStyle(prefs.accentColor)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("下载")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(prefs.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        case .error(let message):
            Text(message).foregroundStyle(Color.muteRed.opacity(0.85))
        }
    }
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
