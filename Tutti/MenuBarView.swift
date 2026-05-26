import SwiftUI
import AppKit
import CoreAudio

private let panelWidth: CGFloat = 320
private let capsuleRadius: CGFloat = 22
private let innerRowRadius: CGFloat = 14
private let capsuleGap: CGFloat = 8

// MARK: - Root

struct MenuBarView: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var profiles: ProfileStore
    @StateObject private var prefs = AppearancePrefs.shared
    @StateObject private var license = LicenseManager.shared
    @StateObject private var trial = TrialManager.shared
    @State private var devicesFolded = false
    @State private var profilesFolded = false
    @State private var showProfileSaveField = false
    @State private var profileSaveDraft = ""
    @State private var showUpgradePulse = false
    @State private var welcomeAcknowledged = UserDefaults.standard.bool(forKey: "tutti.welcome.acknowledged")
    @State private var countdownDismissedDate: String = UserDefaults.standard.string(forKey: "tutti.countdown.dismissedDate") ?? ""
    @State private var trialExpiredDismissedSession: String = UserDefaults.standard.string(forKey: "tutti.trialExpired.dismissedSession") ?? ""
    @Environment(\.tuttiPopover) private var popoverHost

    private var showMaster: Bool { manager.selectedIDs.count >= 2 }
    private var showProfiles: Bool {
        !profiles.profiles.isEmpty || manager.selectedIDs.count >= 2
    }

    var body: some View {
        // Explicit reads keep SwiftUI subscribed to license + trial; the
        // gating logic itself goes through static hasProAccess which won't
        // republish on its own.
        let _ = license.status
        let _ = trial.trialStartDate

        VStack(spacing: capsuleGap) {
            if let variant = bannerVariant {
                UpgradeBanner(
                    variant: variant,
                    purchaseURL: license.purchaseURL,
                    onDismiss: dismissable(variant) ? { dismissBanner(variant) } : nil,
                    onCTA: { handleCTA(variant) }
                )
            }

            StatusCapsule()

            if showMaster {
                MasterCapsule()
            }

            DevicesCapsule(folded: $devicesFolded)

            if showProfiles {
                ProfilesCapsule(
                    folded: $profilesFolded,
                    showSaveField: $showProfileSaveField,
                    draftName: $profileSaveDraft
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.20), value: showProfiles)
        .animation(.easeOut(duration: 0.20), value: profilesFolded)
        .onChange(of: manager.lastUpgradeAttemptID) { _ in
            // Re-show the volume-key upgrade banner each time the user
            // hits the gate, even if they previously dismissed it.
            withAnimation(.easeOut(duration: 0.18)) { showUpgradePulse = true }
        }
        .onChange(of: license.isPro) { isPro in
            // Activate-then-deactivate within the same session must resurface
            // the trialExpired banner — otherwise a prior session dismissal
            // silences the only signal that paid access just went away.
            if !isPro {
                UserDefaults.standard.removeObject(forKey: "tutti.trialExpired.dismissedSession")
                trialExpiredDismissedSession = ""
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(width: panelWidth)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { popoverHost?.updateContentSize(proxy.size) }
                    .onChange(of: proxy.size) { newSize in
                        popoverHost?.updateContentSize(newSize)
                    }
            }
        )
        .background(TransparentWindow(theme: prefs.theme))
        .environmentObject(prefs)
        .preferredColorScheme(prefs.theme.colorScheme)
    }

    // MARK: - Banner state machine

    private var bannerVariant: BannerVariant? {
        // Priority: trialExpired > volume-key upgrade pulse > countdown > welcome
        if trial.hasUsedTrial && !trial.isInTrial && !license.isPro
            && trialExpiredDismissedSession != TrialManager.currentSessionID {
            return .trialExpired
        }
        if showUpgradePulse && !LicenseManager.hasProAccess {
            return .upgrade(reason: manager.pendingUpgradeReason)
        }
        if trial.isInTrial && trial.daysRemaining <= 3
            && countdownDismissedDate != todayKey() {
            return .trialCountdown(daysRemaining: trial.daysRemaining)
        }
        if trial.isInTrial && !welcomeAcknowledged {
            return .welcome(trialDays: 7)
        }
        return nil
    }

    private func dismissable(_ variant: BannerVariant) -> Bool {
        switch variant {
        case .welcome:      return false  // welcome closes via CTA
        case .trialExpired, .upgrade, .trialCountdown: return true
        }
    }

    private func dismissBanner(_ variant: BannerVariant) {
        switch variant {
        case .welcome:
            UserDefaults.standard.set(true, forKey: "tutti.welcome.acknowledged")
            welcomeAcknowledged = true
        case .trialCountdown:
            let key = todayKey()
            UserDefaults.standard.set(key, forKey: "tutti.countdown.dismissedDate")
            countdownDismissedDate = key
        case .upgrade:
            withAnimation { showUpgradePulse = false }
        case .trialExpired:
            let sid = TrialManager.currentSessionID
            UserDefaults.standard.set(sid, forKey: "tutti.trialExpired.dismissedSession")
            withAnimation {
                // Clear any latent volume-key pulse so dismissing trialExpired
                // doesn't immediately surface a second upgrade banner.
                showUpgradePulse = false
                trialExpiredDismissedSession = sid
            }
        }
    }

    private func handleCTA(_ variant: BannerVariant) {
        switch variant {
        case .welcome:
            // "知道了" — acknowledge and dismiss, don't open the purchase URL.
            UserDefaults.standard.set(true, forKey: "tutti.welcome.acknowledged")
            welcomeAcknowledged = true
        case .upgrade, .trialCountdown, .trialExpired:
            NSWorkspace.shared.open(license.purchaseURL)
            if case .upgrade = variant {
                withAnimation { showUpgradePulse = false }
            }
        }
    }

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Status capsule

private struct StatusCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @Environment(\.openTuttiSettings) private var openSettings
    @State private var gearHovering = false

    private var count: Int { manager.selectedIDs.count }
    private var silent: Int { manager.silentCount }
    private var playing: Int { count - silent }
    private var isMuted: Bool { manager.isMuted }

    private var statusText: LocalizedStringKey {
        if count == 0 { return "待机" }
        if isMuted    { return "已静音 · \(count) 个设备" }
        if silent > 0 { return "\(playing) 个输出中 · \(silent) 个静音" }
        if count == 1 { return "正在输出" }
        return "正在输出 · \(count) 个设备"
    }

    private var dotColor: Color {
        if count == 0 { return Color.primary.opacity(0.25) }
        if isMuted    { return .muteRed }
        if silent > 0 { return .statusAmber }
        return .statusGreen
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
                gearButton
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
    }

    private var gearButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.glassTextMid)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(gearHovering ? 0.10 : 0.05))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { gearHovering = $0 }
        .help("设置")
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
        let titleKey: LocalizedStringKey = muted ? "总音量 · 已静音" : "总音量"
        GlassCapsule(tint: muted ? .muteRed : nil) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(titleKey)
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

// MARK: - Profiles capsule

private struct ProfilesCapsule: View {
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var profiles: ProfileStore
    @EnvironmentObject var prefs: AppearancePrefs
    @Binding var folded: Bool
    @Binding var showSaveField: Bool
    @Binding var draftName: String

    private var canSave: Bool { manager.selectedIDs.count >= 2 }

    var body: some View {
        GlassCapsule {
            VStack(spacing: 0) {
                SectionHead(title: "档案", folded: $folded) {
                    if canSave && !showSaveField {
                        Button {
                            withAnimation { showSaveField = true }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("保存当前")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(prefs.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !folded {
                    if showSaveField {
                        ProfileSaveField(draftName: $draftName,
                                         onSubmit: commitSave,
                                         onCancel: cancelSave)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    if !profiles.profiles.isEmpty {
                        let activeUIDs = activeDeviceUIDs
                        VStack(spacing: 1) {
                            ForEach(profiles.profiles) { profile in
                                GlassProfileRow(
                                    profile: profile,
                                    isActive: Set(profile.deviceUIDs) == activeUIDs
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(4)
            .animation(.easeOut(duration: 0.18), value: showSaveField)
        }
    }

    private var activeDeviceUIDs: Set<String> {
        Set(manager.devices
            .filter { manager.selectedIDs.contains($0.id) }
            .map { $0.uid })
    }

    private func commitSave() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Pro gate: free users see the banner and the draft sticks around so
        // they can retry post-upgrade without retyping.
        guard LicenseManager.hasProAccess else {
            manager.triggerUpgradePrompt(reason: .profile)
            return
        }
        let uids = manager.devices
            .filter { manager.selectedIDs.contains($0.id) }
            .map { $0.uid }
        profiles.add(name: name, uids: uids)
        draftName = ""
        showSaveField = false
    }

    private func cancelSave() {
        draftName = ""
        showSaveField = false
    }
}

private struct ProfileSaveField: View {
    @EnvironmentObject var prefs: AppearancePrefs
    @Binding var draftName: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("档案名称", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.glassTextHi)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.glassInnerFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.glassInnerStroke, lineWidth: 0.5)
                        )
                )
                .onSubmit(onSubmit)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.glassTextMid)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("取消")

            Button(action: onSubmit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(draftName.isEmpty ? Color.glassTextLo : prefs.accentColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(draftName.isEmpty)
            .help("保存")
        }
    }
}

// MARK: - Profile row

private struct GlassProfileRow: View {
    let profile: Profile
    let isActive: Bool
    @EnvironmentObject var manager: AudioDeviceManager
    @EnvironmentObject var profiles: ProfileStore
    @EnvironmentObject var prefs: AppearancePrefs
    @State private var hovering = false
    @State private var renaming = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        // Rename/delete buttons MUST be siblings of the apply button, not
        // overlaid in a ZStack. A ZStack lets a tap on ✕ also hit the apply
        // button underneath, which fires the Pro banner on every delete.
        HStack(spacing: 0) {
            Button {
                guard !renaming else { return }
                manager.applyProfile(uids: profile.deviceUIDs)
            } label: {
                HStack(spacing: 10) {
                    GlassIconBadge(symbol: "slider.horizontal.3",
                                   selected: isActive,
                                   accent: prefs.accentColor)
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)

                    if renaming {
                        TextField("名称", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.glassTextHi)
                            .focused($nameFieldFocused)
                            .onSubmit { commitRename() }
                            .onExitCommand { cancelRename() }
                    } else {
                        Text(profile.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.glassTextHi)
                            .lineLimit(1)
                    }

                    Spacer()
                    Text(isActive ? "当前 · \(profile.deviceUIDs.count) 台"
                                  : "\(profile.deviceUIDs.count) 台")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(isActive ? prefs.accentColor : Color.glassTextLo)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if renaming {
                Button { commitRename() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(prefs.accentColor)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("确认重命名")
                .padding(.trailing, 4)
            } else if hovering {
                Button { beginRename() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.glassTextMid)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("重命名")

                Button { profiles.delete(profile) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.muteRed.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除")
                .padding(.trailing, 4)
            }
        }
        .background(
            Group {
                if isActive {
                    prefs.accentColor.opacity(0.18)
                } else if hovering {
                    Color.glassHoverBg
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onChange(of: nameFieldFocused) { focused in
            if !focused && renaming { commitRename() }
        }
    }

    private func beginRename() {
        draftName = profile.name
        renaming = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        profiles.rename(profile, to: draftName)
        renaming = false
    }

    private func cancelRename() {
        renaming = false
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
    let title: LocalizedStringKey
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
    init(title: LocalizedStringKey, trailing: LocalizedStringKey, folded: Binding<Bool>) {
        self.init(title: title, folded: folded) {
            TrailingLabel(text: trailing)
        }
    }
}

private struct TrailingLabel: View {
    let text: LocalizedStringKey
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

// MARK: - Upgrade banner

enum BannerVariant: Equatable {
    case welcome(trialDays: Int)
    case trialCountdown(daysRemaining: Int)
    case trialExpired
    case upgrade(reason: UpgradeReason)  // generic Pro upsell with feature-specific copy
}

private struct UpgradeBanner: View {
    let variant: BannerVariant
    let purchaseURL: URL
    let onDismiss: (() -> Void)?
    let onCTA: () -> Void
    @EnvironmentObject var prefs: AppearancePrefs

    private var iconName: String {
        switch variant {
        case .welcome:        return "party.popper.fill"
        case .trialCountdown: return "sparkles"
        case .trialExpired:   return "exclamationmark.triangle.fill"
        case .upgrade:        return "sparkles"
        }
    }

    private var iconColor: Color {
        if case .trialExpired = variant { return .muteRed }
        return prefs.accentColor
    }

    private var title: LocalizedStringKey {
        switch variant {
        case .welcome:                       return "欢迎使用 Tutti · Pro 试用已开启"
        case .trialCountdown(let days):      return "Pro 试用还剩 \(days) 天"
        case .trialExpired:                  return "Pro 试用已结束 · 音量直控已停用"
        case .upgrade(.volumeTakeover):      return "音量直控需要 Tutti Pro"
        case .upgrade(.profile):             return "档案功能需要 Tutti Pro"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch variant {
        case .welcome(let days):  return "试用期 \(days) 天，所有功能解锁。结束后基础功能仍可正常使用。"
        case .trialCountdown:     return "一次买断 $7.99 解锁永久使用"
        case .trialExpired:       return "一次买断 $7.99，绑定 2 台 Mac"
        case .upgrade:            return "一次买断 $7.99，绑定 2 台 Mac"
        }
    }

    private var ctaLabel: LocalizedStringKey {
        switch variant {
        case .welcome:        return "知道了"
        case .trialExpired:   return "立即购买"
        default:              return "升级"
        }
    }

    private var ctaIsGhost: Bool {
        if case .welcome = variant { return true }
        return false
    }

    private var capsuleTint: Color? {
        if case .trialExpired = variant { return .muteRed }
        return nil
    }

    var body: some View {
        GlassCapsule(tint: capsuleTint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.glassTextHi)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.glassTextMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.glassTextLo)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: onCTA) {
                    Text(ctaLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ctaIsGhost ? prefs.accentColor : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(ctaBackground)
                        .overlay(ctaBorder)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var ctaBackground: some View {
        if ctaIsGhost {
            Capsule().fill(prefs.accentColor.opacity(0.10))
        } else {
            Capsule().fill(
                LinearGradient(
                    colors: [
                        prefs.accentColor.lighter(by: 0.20),
                        prefs.accentColor,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    @ViewBuilder
    private var ctaBorder: some View {
        if ctaIsGhost {
            Capsule().stroke(prefs.accentColor.opacity(0.45), lineWidth: 0.5)
        } else {
            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
    }
}
