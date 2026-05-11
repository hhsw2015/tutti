import SwiftUI
import ApplicationServices
import ServiceManagement

struct SettingsView: View {
    @Binding var visible: Bool
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            header
            hairlineDivider()

            sectionLabel("权限")
            PermissionRow()

            hairlineDivider()
            sectionLabel("启动")
            AutoLaunchRow()
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            hairlineDivider()
            sectionLabel("更新")
            UpdatesSection(updater: updater)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            hairlineDivider()
            footer
        }
        .frame(width: 320)
        .background(Color.chassis)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button { visible = false } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("设置")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Color.textHi)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("MULTIOUT")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.textLo)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack {
            Text("v\(updater.currentVersion)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.textLo)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

struct PermissionRow: View {
    @State private var granted = isAccessibilityGranted()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                if granted {
                    Circle().fill(Color.signal.opacity(0.45))
                        .frame(width: 16, height: 16).blur(radius: 3.5)
                } else {
                    Circle().fill(Color.danger.opacity(0.45))
                        .frame(width: 16, height: 16).blur(radius: 3.5)
                }
                Circle()
                    .fill(granted ? Color.signal : Color.danger)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 16, height: 16)

            Text(granted ? "辅助功能已授权" : "辅助功能未授权")
                .font(.system(size: 12))
                .foregroundStyle(Color.textHi)

            Spacer()

            if !granted {
                Button {
                    openAccessibilitySettings()
                } label: {
                    Text("去授权")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.armed)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .onReceive(timer) { _ in granted = isAccessibilityGranted() }
    }
}

struct AutoLaunchRow: View {
    @State private var enabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button { toggle() } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        .frame(width: 14, height: 14)
                    if enabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.signal)
                    }
                }
                Text("开机自动启动")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textHi)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 8) {
            Button { updater.autoCheckEnabled.toggle() } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3.5)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            .frame(width: 14, height: 14)
                        if updater.autoCheckEnabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.signal)
                        }
                    }
                    Text("启动时自动检查更新")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textHi)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    Task { await updater.check() }
                } label: {
                    Text(isChecking ? "检查中…" : "检查更新")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.chassis)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isChecking ? Color.armedDim : Color.armed)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isChecking)

                statusView
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMid)

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
        case .idle:
            EmptyView()
        case .checking:
            EmptyView()
        case .upToDate:
            Text("已是最新版本").foregroundStyle(Color.textMid)
        case .updateAvailable(let version, let url):
            HStack(spacing: 5) {
                Text("新版本 \(version)")
                    .foregroundStyle(Color.armed)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("下载")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.armed)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        case .error(let message):
            Text(message).foregroundStyle(Color.danger.opacity(0.85))
        }
    }
}

func isAccessibilityGranted() -> Bool {
    AXIsProcessTrustedWithOptions([
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
    ] as CFDictionary)
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
