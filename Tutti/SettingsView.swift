import SwiftUI
import ApplicationServices
import ServiceManagement

struct TuttiSettingsView: View {
    @StateObject private var updater = UpdateChecker()
    @StateObject private var prefs = AppearancePrefs.shared

    var body: some View {
        TabView {
            GeneralTab(updater: updater)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(0)

            AboutTab(updater: updater)
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(1)
        }
        .environmentObject(prefs)
        .frame(width: 480, height: 500)
    }
}

private struct GeneralTab: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        Form {
            Section("主题") { ThemePicker() }
            Section("权限") { PermissionRow() }
            Section("启动") { AutoLaunchRow() }
            Section("更新") { UpdatesSection(updater: updater) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct AboutTab: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            Image(nsImage: TuttiPulseIcon.image(level: 2, size: 64))
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundStyle(prefs.accentColor)

            VStack(spacing: 6) {
                Text("Tutti")
                    .font(.system(size: 24, weight: .semibold))
                Text("One sound, every speaker")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("v\(updater.currentVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await updater.check() }
                } label: {
                    Text(updater.status == .checking ? "检查中…" : "检查更新")
                        .frame(minWidth: 88)
                }
                .controlSize(.regular)
                .disabled(updater.status == .checking)

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出 Tutti")
                        .frame(minWidth: 88)
                }
                .controlSize(.regular)
            }

            updateStatus
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(height: 16)

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.status {
        case .idle, .checking:
            EmptyView()
        case .upToDate:
            Text("已是最新版本")
        case .updateAvailable(let version, let url):
            HStack(spacing: 5) {
                Text("新版本 \(version)")
                    .foregroundStyle(prefs.accentColor)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("下载")
                        .underline()
                        .foregroundStyle(prefs.accentColor)
                }
                .buttonStyle(.plain)
            }
        case .error(let message):
            Text(message).foregroundStyle(Color.muteRed.opacity(0.85))
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
        .frame(maxWidth: .infinity)
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
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
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

    var body: some View {
        let granted = manager.hasAccessibilityPermission
        HStack(spacing: 9) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.statusGreen : Color.muteRed)
            Text(granted ? "辅助功能已授权" : "辅助功能未授权")
            Spacer()
            if !granted {
                Button("去授权") { openAccessibilitySettings() }
            }
        }
    }
}

struct AutoLaunchRow: View {
    @State private var enabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("开机自动启动", isOn: Binding(
            get: { enabled },
            set: { _ in toggle() }
        ))
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

struct UpdatesSection: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        Toggle("启动时自动检查更新", isOn: $updater.autoCheckEnabled)
    }
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
