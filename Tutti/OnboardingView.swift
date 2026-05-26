import SwiftUI
import AppKit

struct OnboardingView: View {
    let onComplete: () -> Void

    @EnvironmentObject var manager: AudioDeviceManager
    @State private var step = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if step == 0 {
                    welcomeStep
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                } else if step == 1 {
                    permissionStep
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                } else {
                    tidyStep
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: step)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 620, height: 520)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            OnboardingStepper(activeStep: 0)

            Spacer().frame(height: 22)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)

            Spacer().frame(height: 18)

            Text("欢迎使用 Tutti")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.glassTextHi)

            Spacer().frame(height: 8)

            Text("把一路音频同时送到多个设备。\n音箱、AirPods、HomePod —— 一键合奏。")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.glassTextMid)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 24)

            HStack(spacing: 10) {
                OnboardingFeatureCard(
                    icon: "speaker.wave.2",
                    title: "多设备同步",
                    sub: "同一音轨，零延迟",
                    pro: false
                )
                OnboardingFeatureCard(
                    icon: "keyboard",
                    title: "高级功能",
                    sub: "音量直控 + 档案切换",
                    pro: true
                )
                OnboardingFeatureCard(
                    icon: "bolt.fill",
                    title: "菜单栏常驻",
                    sub: "随手切换输出",
                    pro: false
                )
            }

            Spacer()

            HStack {
                Spacer()
                OnboardingPrimaryButton(label: "开始", tone: .accent) {
                    withAnimation(.easeInOut(duration: 0.22)) { step = 1 }
                }
            }
        }
    }

    // MARK: - Step 2: Permission

    private var permissionStep: some View {
        let authed = manager.hasAccessibilityPermission
        return VStack(spacing: 0) {
            OnboardingStepper(activeStep: 1)

            Spacer().frame(height: 20)

            // Hero icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(authed ? Color.designAccent.opacity(0.14) : Color.designBrand.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: authed ? "checkmark" : "lock.shield")
                    .font(.system(size: authed ? 28 : 26, weight: .semibold))
                    .foregroundStyle(authed ? Color.designAccent : Color.designBrand)
            }
            .animation(.easeInOut(duration: 0.2), value: authed)

            Spacer().frame(height: 16)

            Text(authed ? "权限已开启" : "开启辅助功能权限")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.glassTextHi)
                .animation(.easeInOut(duration: 0.2), value: authed)

            Spacer().frame(height: 6)

            Text(authed
                 ? "现在你可以用键盘音量键直接控制 Tutti 的聚合输出。"
                 : "授权后，键盘音量键能直接控制 Tutti 的聚合输出。这是 Pro 特性。")
                .font(.system(size: 13))
                .foregroundStyle(Color.glassTextMid)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: authed)

            Spacer().frame(height: 20)

            OnboardingPermRow(authed: authed)

            if !authed {
                Spacer().frame(height: 10)
                OnboardingHintBox()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            // Footer
            HStack(alignment: .center) {
                // Back
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { step = 0 }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Color.glassTextMid)
                }
                .buttonStyle(.plain)

                Spacer()

                if authed {
                    OnboardingPrimaryButton(label: "下一步", tone: .accent) {
                        withAnimation(.easeInOut(duration: 0.22)) { step = 2 }
                    }
                } else {
                    Button("稍后在设置中开启") {
                        withAnimation(.easeInOut(duration: 0.22)) { step = 2 }
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.glassTextLo)
                    .buttonStyle(.plain)

                    Spacer().frame(width: 16)

                    OnboardingPrimaryButton(label: "打开设置", tone: .primary) {
                        openAccessibilitySettings()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authed)
    }

    // MARK: - Step 3: Tidy the menu bar

    private var tidyStep: some View {
        VStack(spacing: 0) {
            OnboardingStepper(activeStep: 2)

            Spacer().frame(height: 20)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.designBrand.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.designBrand)
            }

            Spacer().frame(height: 16)

            Text("整理你的菜单栏")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.glassTextHi)

            Spacer().frame(height: 6)

            Text("Tutti 现在能完整接管音频输出。系统自带的音量图标可以隐藏，菜单栏会清爽很多。")
                .font(.system(size: 13))
                .foregroundStyle(Color.glassTextMid)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 12)

            Spacer().frame(height: 20)

            OnboardingTidyHintBox()

            Spacer()

            HStack(alignment: .center) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { step = 1 }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Color.glassTextMid)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("稍后再说") { onComplete() }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.glassTextLo)
                    .buttonStyle(.plain)

                Spacer().frame(width: 16)

                OnboardingPrimaryButton(label: "打开系统设置", tone: .primary) {
                    openControlCenterSoundSettings()
                    onComplete()
                }
            }
        }
    }
}

// MARK: - Primitives

private struct OnboardingStepper: View {
    let activeStep: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                if i == activeStep {
                    Capsule()
                        .fill(Color.designBrand)
                        .frame(width: 22, height: 6)
                } else {
                    Circle()
                        .fill(Color.glassTextMid.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeStep)
    }
}

private struct OnboardingFeatureCard: View {
    let icon: String
    let title: String
    let sub: String
    let pro: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.glassInnerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.glassInnerStroke, lineWidth: 0.5)
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.glassTextHi)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.glassTextHi)
                Text(sub)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.glassTextMid)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if pro {
                Text("PRO")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.designBrand)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.designBrand.opacity(0.14)))
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.designCardEdge, lineWidth: 0.5)
                )
        )
    }
}

private struct OnboardingPermRow: View {
    let authed: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(authed ? Color.designAccent.opacity(0.14) : Color.glassInnerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(authed ? Color.designAccent.opacity(0.25) : Color.glassInnerStroke, lineWidth: 0.5)
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "keyboard")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(authed ? Color.designAccent : Color.glassTextHi)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("拦截 F11 / F12 与音量键")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.glassTextHi)
                Text("替代系统默认，使音量调节作用于聚合输出而不是单一设备。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.glassTextMid)
                    .lineSpacing(2)
            }

            Spacer()

            if authed {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("已授权")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Color.designAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.designAccent.opacity(0.14)))
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.glassTextMid.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text("未授权")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.glassTextMid)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.designCardEdge, lineWidth: 0.5)
                )
        )
    }
}

private struct OnboardingHintBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("点击「打开设置」会跳转到 ")
            + Text("系统设置 › 隐私与安全性 › 辅助功能").font(.system(size: 12, design: .monospaced))
            + Text("，把 Tutti 的开关打开即可。"))
            .font(.system(size: 12))
            .foregroundStyle(Color.glassTextMid)
            .lineSpacing(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.designCardEdge.opacity(1.5))
                )
        )
    }
}

private struct OnboardingTidyHintBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("点击「打开系统设置」会跳到 ")
            + Text("控制中心").font(.system(size: 12, design: .monospaced))
            + Text("，把 ")
            + Text("声音").font(.system(size: 12, design: .monospaced))
            + Text(" 一栏的「在菜单栏中显示」改为「不显示」即可。"))
            .font(.system(size: 12))
            .foregroundStyle(Color.glassTextMid)
            .lineSpacing(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.designCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.designCardEdge.opacity(1.5))
                )
        )
    }
}

private enum OnboardingButtonTone { case accent, primary }

private struct OnboardingPrimaryButton: View {
    let label: String
    let tone: OnboardingButtonTone
    let action: () -> Void

    var bg: Color { tone == .accent ? Color.designAccent : Color.designPrimary }
    var fg: Color { tone == .accent ? Color.designPillActiveFg : .white }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13.5, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bg)
            )
        }
        .buttonStyle(.plain)
    }
}

