import SwiftUI
import AppKit

enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, blue, purple, red, green, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
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

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.accentKey) ?? ""
        self.accent = AccentChoice(rawValue: raw) ?? .orange
    }
}

extension Color {
    static let glassTextHi  = Color.white.opacity(0.96)
    static let glassTextMid = Color.white.opacity(0.70)
    static let glassTextLo  = Color.white.opacity(0.55)
    static let glassTextDim = Color.white.opacity(0.45)

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

struct GlassCapsule<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .glassEffect(
                tint.map { .regular.tint($0.opacity(0.18)) } ?? .regular,
                in: shape
            )
            .overlay(GlassHighlight().clipShape(shape))
            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
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
