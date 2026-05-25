import AppKit
import SwiftUI

@MainActor
final class VolumeOSDController {
    static let shared = VolumeOSDController()
    private init() {}

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var dismissWork: DispatchWorkItem?

    func show(volume: Float, isMuted: Bool, deviceNames: [String]) {
        let isDark = Self.resolveIsDark()
        let osdView = AnyView(
            VolumeOSDView(volume: volume, isMuted: isMuted, deviceNames: deviceNames, isDark: isDark)
        )

        if let hosting = hostingView {
            hosting.rootView = osdView
        } else {
            let hosting = NSHostingView(rootView: osdView)
            hostingView = hosting
            buildPanel(contentView: hosting)
        }

        panel?.orderFrontRegardless()
        scheduleDismiss()
    }

    private static func resolveIsDark() -> Bool {
        switch AppearancePrefs.shared.theme {
        case .light: return false
        case .dark:  return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    private func buildPanel(contentView: NSView) {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isMovable = false
        p.contentView = contentView

        // Panel is larger than the visible OSD so the SwiftUI .shadow() has room
        // to extend beyond the rounded rectangle instead of being clipped into
        // visible square edges at the corners.
        let size = CGSize(width: 420, height: 160)
        if let screen = NSScreen.main {
            let sf = screen.frame
            let origin = CGPoint(x: sf.midX - size.width / 2, y: sf.minY + 100)
            p.setFrame(CGRect(origin: origin, size: size), display: false)
        }

        panel = p
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

// MARK: - Blur backdrop (independent of NSWindow appearance)

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = .sidebar
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - OSD View

private struct VolumeOSDView: View {
    let volume: Float
    let isMuted: Bool
    let deviceNames: [String]
    let isDark: Bool

    private var accent: Color { Color(nsColor: .controlAccentColor) }
    private static let mutedTop = Color(red: 255/255, green: 122/255, blue: 114/255)
    private static let mutedBot = Color(red: 255/255, green: 69/255, blue: 58/255)

    private var surfaceBg: LinearGradient {
        isDark
            ? LinearGradient(
                colors: [
                    Color(red: 60/255, green: 60/255, blue: 66/255).opacity(0.82),
                    Color(red: 40/255, green: 40/255, blue: 46/255).opacity(0.76),
                ],
                startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [
                    Color.white.opacity(0.84),
                    Color(red: 248/255, green: 246/255, blue: 242/255).opacity(0.78),
                ],
                startPoint: .top, endPoint: .bottom)
    }

    private var textPrimary: Color {
        isDark ? .white.opacity(0.96) : Color(red: 28/255, green: 24/255, blue: 20/255).opacity(0.92)
    }

    private var textSub: Color {
        isDark ? Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.55)
               : Color(red: 60/255,  green: 50/255,  blue: 40/255).opacity(0.55)
    }

    private var trackBg: Color {
        isDark ? .white.opacity(0.16) : .black.opacity(0.10)
    }

    private var labelText: Text {
        switch deviceNames.count {
        case 0: return Text(verbatim: "Tutti")
        case 1: return Text(verbatim: deviceNames[0])
        default: return Text("\(deviceNames.count) 个设备")
        }
    }

    private var speakerIcon: String {
        guard !isMuted && volume > 0 else { return "speaker.slash.fill" }
        if volume < 0.35 { return "speaker.fill" }
        if volume < 0.70 { return "speaker.wave.1.fill" }
        return "speaker.wave.3.fill"
    }

    private var iconGradient: LinearGradient {
        isMuted
            ? LinearGradient(colors: [Self.mutedTop, Self.mutedBot], startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [accent.opacity(0.7).lighter(), accent],
                startPoint: .top, endPoint: .bottom)
    }

    private var volPct: Int { isMuted ? 0 : min(100, Int((volume * 100).rounded())) }
    private var fillFraction: CGFloat { isMuted ? 0 : CGFloat(volume).clamped(to: 0...1) }

    var body: some View {
        HStack(spacing: 12) {
            // Speaker circle
            ZStack {
                Circle()
                    .fill(iconGradient)
                    .frame(width: 34, height: 34)
                    .shadow(color: (isMuted ? Self.mutedBot : accent).opacity(0.45), radius: 6, y: 2)
                Image(systemName: speakerIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }

            // Label + slider
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    labelText
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(isMuted ? "—" : "\(volPct)%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(textSub)
                }

                // Volume slider (read-only visual)
                GeometryReader { geo in
                    let w = geo.size.width
                    let fill = fillFraction * w
                    let knobR: CGFloat = 7
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(trackBg)
                            .frame(height: 6)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.7), accent],
                                    startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(0, fill), height: 6)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white, Color(white: 0.94)],
                                    center: .init(x: 0.35, y: 0.25),
                                    startRadius: 0, endRadius: knobR * 2)
                            )
                            .frame(width: knobR * 2, height: knobR * 2)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            .offset(x: max(0, fill - knobR))
                    }
                }
                .frame(height: 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.clear)
                .background(
                    VisualEffectBlur()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(surfaceBg)
                )
                .shadow(
                    color: isDark ? .black.opacity(0.32) : Color(red: 60/255, green: 40/255, blue: 20/255).opacity(0.14),
                    radius: 14, y: 6
                )
                .shadow(color: .black.opacity(isDark ? 0.18 : 0.06), radius: 4, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Color {
    func lighter(by amount: Double = 0.25) -> Color {
        Color(nsColor: NSColor(self).blended(withFraction: amount, of: .white) ?? NSColor(self))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
