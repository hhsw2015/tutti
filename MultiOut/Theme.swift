import SwiftUI
import AppKit

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, orange, blue, purple, red, green, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .orange: return Color(red: 1.00, green: 0.624, blue: 0.039)
        case .blue:   return Color(red: 0.039, green: 0.518, blue: 0.996)
        case .purple: return Color(red: 0.749, green: 0.353, blue: 0.949)
        case .red:    return Color(red: 1.00, green: 0.271, blue: 0.227)
        case .green:  return Color(red: 0.188, green: 0.820, blue: 0.345)
        case .yellow: return Color(red: 1.00, green: 0.839, blue: 0.039)
        }
    }
}

@MainActor
final class AppearancePrefs: ObservableObject {
    static let shared = AppearancePrefs()

    private static let accentKey = "accentChoice"

    @Published var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey) }
    }

    private var systemColorObserver: NSObjectProtocol?

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.accentKey) ?? ""
        self.accent = AccentChoice(rawValue: raw) ?? .system

        // System accent can change at any time via System Settings.
        // Republish when the user is on .system so accent-tinted views refresh.
        systemColorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.accent == .system else { return }
                self.objectWillChange.send()
            }
        }
    }
}

extension Color {
    // Semantic foreground tokens — resolve to NSColor.labelColor / secondaryLabelColor / ...
    // which adapt for vibrancy: dark on light glass, light on dark glass.
    static let glassTextHi  = Color.primary
    static let glassTextMid = Color.secondary
    static let glassTextLo  = Color(nsColor: .tertiaryLabelColor)
    static let glassTextDim = Color(nsColor: .quaternaryLabelColor)

    // Material strokes / fills that should adapt the same way as text.
    static let glassBorder      = Color.primary.opacity(0.15)
    static let glassInnerFill   = Color.primary.opacity(0.08)
    static let glassInnerStroke = Color.primary.opacity(0.18)
    static let glassHoverBg     = Color.primary.opacity(0.06)

    static let statusGreen  = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let muteRed      = Color(red: 1.00,  green: 0.271, blue: 0.227)

    static let panelBackdrop = Color(red: 0.06, green: 0.05, blue: 0.10)

    func lighter(by amount: CGFloat) -> Color {
        Color(nsColor: NSColor(self).blended(withFraction: amount, of: .white) ?? NSColor(self))
    }

    func darker(by amount: CGFloat) -> Color {
        Color(nsColor: NSColor(self).blended(withFraction: amount, of: .black) ?? NSColor(self))
    }
}

struct GlassHighlight: View {
    var body: some View {
        RadialGradient(
            colors: [Color.white.opacity(0.25), .clear],
            center: .init(x: 0.30, y: 0.0),
            startRadius: 0,
            endRadius: 180
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

private struct GlassMaterialBackground: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.fill(tint?.opacity(0.14) ?? .clear))
    }
}

struct GlassCapsule<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .modifier(GlassMaterialBackground(cornerRadius: cornerRadius, tint: tint))
            .overlay(GlassHighlight().clipShape(shape))
            .overlay(shape.stroke(Color.glassBorder, lineWidth: 0.5))
    }
}

struct StatusDot: View {
    let color: Color
    var active: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(active ? 0.55 : 0))
                .frame(width: 14, height: 14)
                .blur(radius: 3)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
        }
        .frame(width: 14, height: 14)
    }
}

/// Makes the hosting NSWindow fully transparent and hides the system-added
/// NSVisualEffectView, so the desktop wallpaper shows through the gaps
/// between glass capsules.
struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.setAccessibilityHidden(true)
        DispatchQueue.main.async { configure(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        hideEffectViews(window.contentView)
    }

    private func hideEffectViews(_ view: NSView?) {
        guard let view else { return }
        for sub in view.subviews {
            if sub is NSVisualEffectView { sub.isHidden = true }
            hideEffectViews(sub)
        }
    }
}
