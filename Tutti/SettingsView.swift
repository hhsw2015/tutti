import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement

// MARK: - Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, license, about
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .general: return "通用"
        case .license: return "许可"
        case .about:   return "关于"
        }
    }
}

// MARK: - Root

struct TuttiSettingsView: View {
    @StateObject private var updater = UpdateChecker()
    @StateObject private var prefs = AppearancePrefs.shared
    @StateObject private var license = LicenseManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var showDeactivateConfirm = false
    // Hoisted so the value survives tab switches — LicenseTab is rebuilt each
    // time it's the active tab, so its own @State would reset and re-prefill.
    @State private var licenseInputKey: String = ""
    @State private var licenseDidPrefill: Bool = false

    var body: some View {
        ZStack {
            SettingsGlassBackground()

            VStack(spacing: 0) {
                HeaderBar(selectedTab: $selectedTab)
                    .padding(.bottom, 18)

                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralTab(updater: updater)
                        case .license:
                            LicenseTab(
                                showDeactivateConfirm: $showDeactivateConfirm,
                                inputKey: $licenseInputKey,
                                didPrefill: $licenseDidPrefill
                            )
                        case .about:
                            AboutTab(updater: updater)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        .frame(width: 720, height: 600)
        .environmentObject(prefs)
        .preferredColorScheme(prefs.theme.colorScheme)
        .onChange(of: license.status) { newStatus in
            // Any transition back to inactive (user deactivate or server
            // revoke) re-arms the prefill so the saved key is offered once
            // more on the next appearance of the free tier card.
            if newStatus == .inactive {
                licenseDidPrefill = false
                licenseInputKey = ""
            }
        }
        .alert("切换语言需要重启 Tutti", isPresented: $prefs.languageRestartPending) {
            Button("立即重启") { prefs.relaunch() }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("重启后菜单栏、面板以及系统通知会切换为新语言。")
        }
        .confirmationDialog(
            "停用这台 Mac?",
            isPresented: $showDeactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("停用", role: .destructive) {
                Task { try? await license.deactivate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("释放 1 台设备名额。停用后基础功能仍可使用，仅高级功能（音量直控和预设保存）会被禁用，可随时用同一密钥重新激活。")
        }
    }
}

// MARK: - Background

private struct SettingsGlassBackground: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Color.designGlassTint)
            .ignoresSafeArea()
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        ZStack {
            // Centered tab pill
            HStack { Spacer(); PillTabs(selected: $selectedTab); Spacer() }

            // Left-edge title, padded to clear traffic-light controls.
            HStack {
                Text("设置")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.leading, 72)
                Spacer()
            }
        }
        .frame(height: 36)
    }
}

private struct PillTabs: View {
    @Binding var selected: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases) { tab in
                let isActive = selected == tab
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { selected = tab }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isActive ? Color.designPillActiveFg : Color.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.designPillActiveBg : Color.clear)
                                .shadow(color: isActive ? Color.black.opacity(0.18) : .clear,
                                        radius: 3, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.designBtnBg)
                .overlay(Capsule().stroke(Color.designBtnEdge, lineWidth: 0.5))
        )
    }
}

// MARK: - Card row primitive

private struct CardRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: LocalizedStringKey,
         subtitle: LocalizedStringKey? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.designCardEdge, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: AppearancePrefs
    @EnvironmentObject var audio: AudioDeviceManager
    @StateObject private var license = LicenseManager.shared
    @StateObject private var trial = TrialManager.shared
    @State private var autoLaunchEnabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        // Explicit reads so SwiftUI re-renders the gated row when license
        // or trial state changes. hasProAccess is static, so without these
        // SwiftUI has nothing to subscribe to.
        let _ = license.status
        let _ = trial.trialStartDate

        VStack(spacing: 10) {
            CardRow("语言",
                    subtitle: "切换后需重启 Tutti 才会全部生效。") {
                LanguageSelect()
            }

            CardRow("外观",
                    subtitle: "跟随系统时，会随浅/深色切换菜单栏与所有面板。") {
                ThemeSegmented()
            }

            CardRow("开机自动启动",
                    subtitle: "登录系统时静默打开 Tutti，并以菜单栏图标方式驻留。") {
                Toggle("", isOn: Binding(
                    get: { autoLaunchEnabled },
                    set: { _ in toggleAutoLaunch() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Color.designAccent)
            }

            if LicenseManager.hasProAccess {
                CardRow("辅助功能权限",
                        subtitle: "授权后，键盘音量键能直接控制聚合输出。") {
                    if audio.hasAccessibilityPermission {
                        StatusPill(label: "已授权", tone: .accent)
                    } else {
                        Button("去授权") { openAccessibilitySettings() }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
            } else {
                CardRow("高级功能 · Pro",
                        subtitle: "升级 Pro 后，键盘音量键和菜单栏滚轮直接调聚合输出，常用设备组合存为预设一键切换。") {
                    ProUpgradeButton(purchaseURL: license.purchaseURL)
                }
            }

            VStack(spacing: 0) {
                CardRow("自动检查更新",
                        subtitle: "从 GitHub Releases 拉取，仅在有新版本时通知一次。") {
                    HStack(spacing: 10) {
                        Text("v\(updater.currentVersion)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await updater.check() }
                        } label: {
                            Text(updater.status == .checking ? "检查中…" : "检查更新")
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(updater.status == .checking)
                        Toggle("", isOn: $updater.autoCheckEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(Color.designAccent)
                    }
                }
                UpdateStatusInline(updater: updater)
            }

            CardRow("退出 Tutti",
                    subtitle: "完全退出应用，不再驻留菜单栏。") {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出")
                }
                .buttonStyle(DangerGhostButtonStyle())
            }
        }
    }

    private func toggleAutoLaunch() {
        if autoLaunchEnabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        autoLaunchEnabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - General sub-controls

private struct LanguageSelect: View {
    @EnvironmentObject var prefs: AppearancePrefs

    var body: some View {
        Menu {
            ForEach(SupportedLanguage.allCases) { lang in
                Button {
                    prefs.language = lang
                } label: {
                    HStack {
                        Text(verbatim: lang.displayName)
                        if prefs.language == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: prefs.language.displayName)
                    .font(.system(size: 13))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.designBtnBg)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.designBtnEdge, lineWidth: 0.5))
            )
            .frame(minWidth: 120, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct ThemeSegmented: View {
    @EnvironmentObject var prefs: AppearancePrefs

    private struct Item: Identifiable {
        let id: ThemeChoice
        let label: LocalizedStringKey
        let symbol: String
    }

    private let items: [Item] = [
        .init(id: .light,  label: "浅色", symbol: "sun.max"),
        .init(id: .dark,   label: "深色", symbol: "moon"),
        .init(id: .system, label: "系统", symbol: "circle.lefthalf.filled"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isActive = prefs.theme == item.id
                Button {
                    prefs.theme = item.id
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                        Text(item.label)
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(isActive ? Color.designAccent : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(isActive ? Color.designAccent.opacity(0.16) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.designBtnBg)
                .overlay(Capsule().stroke(Color.designBtnEdge, lineWidth: 0.5))
        )
    }
}

// MARK: - License tab

private struct LicenseTab: View {
    @EnvironmentObject var prefs: AppearancePrefs
    @StateObject private var license = LicenseManager.shared
    @Binding var showDeactivateConfirm: Bool
    @Binding var inputKey: String
    @Binding var didPrefill: Bool
    @State private var isWorking = false
    @State private var feedback: Feedback?
    @State private var copiedFlash = false

    enum Feedback: Equatable {
        case info(String)
        case error(String)
    }

    var body: some View {
        Group {
            if license.isPro {
                activatedCard
            } else {
                freeTierCard
            }

            if let feedback {
                FeedbackBanner(feedback: feedback)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: feedback)
    }

    // MARK: Activated

    private var activatedCard: some View {
        VStack(spacing: 14) {
            VerifiedSeal(size: 92)

            Text("感谢您购买 Tutti")
                .font(.system(size: 19, weight: .bold))

            Text("Pro 已解锁。键盘音量键和菜单栏滚轮可直接调聚合输出，常用设备组合也能存为预设一键切换。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, -4)

            if let displayKey = formattedLicenseKey() {
                Button(action: copyKey) {
                    HStack(spacing: 10) {
                        Text(verbatim: displayKey)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(copiedFlash ? Color.designAccent : Color.secondary)
                        Image(systemName: copiedFlash ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: copiedFlash ? .bold : .regular))
                            .foregroundStyle(copiedFlash ? Color.designAccent : Color.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.designBtnBg)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(copiedFlash ? Color.designAccent.opacity(0.5) : Color.designBtnEdge,
                                        lineWidth: 0.5))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("复制完整密钥到剪贴板")
                .padding(.top, 4)
            }

            Group {
                if copiedFlash {
                    Text("已复制到剪贴板")
                        .foregroundStyle(Color.designAccent)
                } else {
                    graceOrStatusLine
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .animation(.easeOut(duration: 0.15), value: copiedFlash)

            Button {
                showDeactivateConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("停用这台 Mac")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.designCardEdge, lineWidth: 0.5))
        )
    }

    @ViewBuilder
    private var graceOrStatusLine: some View {
        switch license.status {
        case .offlineGrace(let daysLeft):
            Text("离线模式 · 还可使用 \(daysLeft) 天")
        case .expired:
            Text("Pro 已过期，请联网验证或重新激活")
        case .activated, .inactive:
            Text("此密钥可在 2 台 Mac 上使用")
        }
    }

    private func formattedLicenseKey() -> String? {
        guard let key = license.maskedKey else { return nil }
        return key
    }

    private func copyKey() {
        guard license.copyKeyToPasteboard() else { return }
        withAnimation(.easeOut(duration: 0.15)) { copiedFlash = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeIn(duration: 0.2)) { copiedFlash = false }
        }
    }

    // MARK: Free tier

    private var freeTierCard: some View {
        VStack(spacing: 16) {
            // Free-tier header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.designToggleOff)
                        .frame(width: 38, height: 38)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("免费版 · 基础功能完整可用")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Pro 让你用键盘音量键和菜单栏滚轮直接调聚合输出，还能把常用设备组合存为预设一键切换。一次买断 $7.99，含所有未来 Pro 功能升级。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.designBtnBg)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.designBtnEdge, lineWidth: 0.5))
            )

            // License key input
            TextField("", text: $inputKey, prompt:
                Text("粘贴邮件中的许可证密钥")
                    .foregroundColor(.secondary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.designBtnBg)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.designBtnEdge, lineWidth: 0.5))
            )
            .disableAutocorrection(true)

            // Activate button
            Button {
                Task { await runActivate() }
            } label: {
                Text(isWorking ? "激活中…" : "激活")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(activateForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(activateBackground)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.designBtnEdge, lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isWorking || inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Footer row
            HStack {
                Text("一次付费 · 可在 2 台 Mac 上使用")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSWorkspace.shared.open(license.purchaseURL)
                } label: {
                    HStack(spacing: 4) {
                        Text("购买许可证")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color.designAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.designCardEdge, lineWidth: 0.5))
        )
        // Prefill once per "inactive session": the first appearance after
        // the free tier card becomes visible (either on first open while
        // already inactive, or right after a deactivate). Tab switches and
        // re-renders within the same session don't refill, so a manual
        // clear or edit sticks.
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            if inputKey.isEmpty, let last = license.lastUsedKey {
                inputKey = last
            }
        }
    }

    private var canActivate: Bool {
        !isWorking && !inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activateBackground: Color {
        canActivate ? Color.designAccent.opacity(0.18) : Color.designBtnBg
    }

    private var activateForeground: Color {
        canActivate ? Color.designAccent : Color.secondary
    }

    private func runActivate() async {
        feedback = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await LicenseManager.shared.activate(licenseKey: inputKey)
            inputKey = ""
            feedback = .info(String(localized: "激活成功"))
        } catch {
            feedback = .error(error.localizedDescription)
        }
    }
}

private struct FeedbackBanner: View {
    let feedback: LicenseTab.Feedback

    var body: some View {
        let (icon, color, text): (String, Color, String) = {
            switch feedback {
            case .info(let s):  return ("checkmark.circle.fill", .designAccent, s)
            case .error(let s): return ("exclamationmark.triangle.fill", .designDanger, s)
            }
        }()

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(verbatim: text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 0.5))
        )
        .padding(.top, 6)
    }
}

// MARK: - Verified Seal (Apple-style scalloped badge)

private struct VerifiedSeal: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.designAccent.opacity(0.16))
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 18)

            // Scalloped seal in Color.designAccent
            ScallopedBadge()
                .fill(Color.designAccent)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .black))
                        .foregroundStyle(Color(red: 0.06, green: 0.16, blue: 0.11))
                )
        }
        .frame(width: size * 1.4, height: size * 1.4)
    }
}

/// 16-point scalloped seal — a tile of 16 outer points around a circle.
private struct ScallopedBadge: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width / 2
        let inner = outer * 0.88
        let points = 16
        var path = Path()
        for i in 0..<(points * 2) {
            let theta = (Double(i) / Double(points * 2)) * 2 * .pi - .pi / 2
            let r = (i % 2 == 0) ? outer : inner
            let p = CGPoint(x: center.x + cos(theta) * r,
                            y: center.y + sin(theta) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - About tab

private struct AboutTab: View {
    @ObservedObject var updater: UpdateChecker
    @EnvironmentObject var prefs: AppearancePrefs

    /// Live app-bundle icon — same artwork as the Dock icon, scaled.
    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .padding(.bottom, 14)

            Text(verbatim: "Tutti")
                .font(.system(size: 34, weight: .bold))

            Text(verbatim: "One sound, every speaker")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text(verbatim: "v\(updater.currentVersion)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text("把一路音频同时送到多个输出设备的 macOS 菜单栏小工具。基于 CoreAudio aggregate device，原生 SwiftUI + AppKit 互操作，无第三方依赖。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 22)

            HStack(spacing: 28) {
                FooterLink("GitHub", url: "https://github.com/BarryBarrywu/tutti")
                FooterLink("反馈", url: "https://github.com/BarryBarrywu/tutti/issues")
                FooterLink("致谢", url: "https://github.com/BarryBarrywu/tutti#acknowledgements")
            }
            .padding(.top, 24)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.designCardEdge, lineWidth: 0.5))
        )
    }
}

private struct FooterLink: View {
    let title: LocalizedStringKey
    let url: String

    init(_ title: LocalizedStringKey, url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared subviews

private struct StatusPill: View {
    let label: LocalizedStringKey
    enum Tone { case accent, plain }
    let tone: Tone

    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch tone {
            case .accent: return (Color.designAccent, Color.designAccent.opacity(0.18))
            case .plain:  return (Color.primary, Color.designBtnBg)
            }
        }()
        return Text(label)
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }
}

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.designBtnBg)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.designBtnEdge, lineWidth: 0.5))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

private struct DangerGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.designDanger)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.designDanger.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.designDanger.opacity(0.25), lineWidth: 0.5))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

/// Slim status line shown directly beneath the "自动检查更新" card after a
/// manual check — keeps the card itself compact while still surfacing the
/// outcome (up to date / new version / error).
private struct UpdateStatusInline: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        Group {
            switch updater.status {
            case .idle, .checking:
                EmptyView()
            case .upToDate:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.designAccent)
                    Text("已是最新版本")
                        .foregroundStyle(.secondary)
                }
            case .updateAvailable(let version, let url):
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.designAccent)
                    Text("新版本 \(version)")
                        .foregroundStyle(.secondary)
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("下载")
                            .underline()
                            .foregroundStyle(Color.designAccent)
                    }
                    .buttonStyle(.plain)
                }
            case .error(let message):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.designDanger)
                    Text(verbatim: message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11.5))
        .padding(.top, 6)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Accessibility settings helper

func openAccessibilitySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
    NSWorkspace.shared.open(url)
}

func openControlCenterSoundSettings() {
    // Verified on macOS 26.5 — opens System Settings → Control Center
    // where the user toggles the Sound menu bar entry.
    guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
}
