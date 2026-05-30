import SwiftUI
import AppKit

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "laptopcomputer"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

/// User-facing language preference. "auto" follows the system; everything else
/// pins Tutti to a specific locale by writing `AppleLanguages`. Switching
/// requires a relaunch — SwiftUI / Foundation only re-resolves strings against
/// `Bundle.main` at process startup.
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case auto
    case english            = "en"
    case simplifiedChinese  = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese           = "ja"
    case korean             = "ko"
    case french             = "fr"
    case german             = "de"
    case italian            = "it"
    case spanish            = "es"

    var id: String { rawValue }

    /// Always rendered in the target language so users searching for their
    /// language can find it without already understanding the current UI.
    var displayName: String {
        switch self {
        case .auto:                return String(localized: "自动")
        case .english:             return "English"
        case .simplifiedChinese:   return "中文"
        case .traditionalChinese:  return "繁體中文"
        case .japanese:            return "日本語"
        case .korean:              return "한국어"
        case .french:              return "Français"
        case .german:              return "Deutsch"
        case .italian:             return "Italiano"
        case .spanish:             return "Español"
        }
    }
}

@MainActor
final class AppearancePrefs: ObservableObject {
    static let shared = AppearancePrefs()

    private static let themeKey = "themeChoice"
    private static let languageKey = "tutti.language"
    private static let appleLanguagesKey = "AppleLanguages"

    @Published var theme: ThemeChoice {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    @Published var language: SupportedLanguage {
        didSet {
            guard oldValue != language else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            applyLanguageOverride(language)
            languageRestartPending = true
        }
    }

    /// Set by `language` didSet; SettingsView observes this to show the
    /// "restart to apply" alert.
    @Published var languageRestartPending = false

    /// macOS system accent. Republishes via the observer below when the user
    /// changes it in System Settings.
    var accentColor: Color { Color(nsColor: .controlAccentColor) }

    private var systemColorObserver: NSObjectProtocol?

    private init() {
        let rawTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        self.theme = ThemeChoice(rawValue: rawTheme) ?? .system

        let rawLang = UserDefaults.standard.string(forKey: Self.languageKey) ?? ""
        self.language = SupportedLanguage(rawValue: rawLang) ?? .auto

        systemColorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }

    /// Apply saved language preference. Called once from app startup to make
    /// sure `AppleLanguages` is set before SwiftUI / NSWindow titles render.
    static func applySavedLanguageAtStartup() {
        let raw = UserDefaults.standard.string(forKey: languageKey) ?? ""
        let lang = SupportedLanguage(rawValue: raw) ?? .auto
        applyLanguageOverride(lang)
    }

    private static func applyLanguageOverride(_ lang: SupportedLanguage) {
        if lang == .auto {
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        } else {
            UserDefaults.standard.set([lang.rawValue], forKey: appleLanguagesKey)
        }
    }

    /// Instance wrapper around the static so `didSet` can call it.
    private func applyLanguageOverride(_ lang: SupportedLanguage) {
        Self.applyLanguageOverride(lang)
    }

    /// Quit + relaunch via `open -n`. Called when the user accepts the
    /// restart prompt after switching language. If the spawn fails we leave
    /// the current process running so the user isn't stranded.
    func relaunch() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            NSLog("Tutti relaunch failed: \(error)")
            return
        }
        NSApp.terminate(nil)
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
    static let statusAmber  = Color(red: 1.00,  green: 0.667, blue: 0.000)
    static let muteRed      = Color(red: 1.00,  green: 0.271, blue: 0.227)

    static let panelBackdrop = Color(red: 0.06, green: 0.05, blue: 0.10)

    // MARK: - Settings design tokens (from Tutti Settings design canvas)

    /// Follows the macOS system accent color so badges, toggles, and Pro chips
    /// match whatever the user picks in System Settings > Appearance > Accent.
    static let designAccent  = Color(nsColor: .controlAccentColor)
    /// Tutti brand pink / coral, used for the Broadcast Dot mark in About.
    static let designBrand   = Color(light: hex("E04E70"), dark: hex("F2728E"))
    /// System-blue primary action (used on the language-restart confirm).
    static let designPrimary = Color(light: hex("0A66FF"), dark: hex("3D7BFF"))
    /// Destructive red for "Deactivate this Mac" confirm.
    static let designDanger  = Color(light: hex("C8362E"), dark: hex("E25656"))

    /// Subtle tint dropped behind the .regularMaterial settings window —
    /// pulls the glass toward the warm cream/brown look in the mockup.
    static let designGlassTint = Color(
        light: Color(red: 1.0, green: 0.98, blue: 0.94).opacity(0.45),
        dark:  Color(red: 0.14, green: 0.09, blue: 0.06).opacity(0.45)
    )

    /// Card fill: a low-opacity white in dark mode, near-white in light mode.
    static let designCardBg = Color(
        light: Color.white.opacity(0.55),
        dark:  Color(red: 1.0, green: 0.97, blue: 0.92).opacity(0.04)
    )
    static let designCardEdge = Color(
        light: Color.black.opacity(0.07),
        dark:  Color.white.opacity(0.06)
    )

    /// Pill / button container with a slight inset glass feel.
    static let designBtnBg = Color(
        light: Color.black.opacity(0.05),
        dark:  Color.white.opacity(0.08)
    )
    static let designBtnEdge = Color(
        light: Color.black.opacity(0.10),
        dark:  Color.white.opacity(0.12)
    )

    /// Track for unselected toggle states.
    static let designToggleOff = Color(
        light: Color.black.opacity(0.14),
        dark:  Color.white.opacity(0.12)
    )

    /// Active pill backdrop in the tab segmented control.
    static let designPillActiveBg = Color.white
    static let designPillActiveFg = Color(red: 0.10, green: 0.05, blue: 0.04)

    private static func hex(_ string: String) -> Color {
        let cleaned = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    /// Light/dark adaptive Color built from two SwiftUI Colors.
    init(light: Color, dark: Color) {
        let lightNS = NSColor(light)
        let darkNS  = NSColor(dark)
        let dynamic = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
            return match == .darkAqua ? darkNS : lightNS
        }
        self.init(nsColor: dynamic)
    }

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
            .overlay(
                shape
                    .fill(tint?.opacity(0.14) ?? .clear)
                    .allowsHitTesting(false)
            )
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
/// between glass capsules. Also applies the theme override so materials
/// (which key off the NSWindow's appearance, not SwiftUI's color scheme)
/// switch alongside semantic foreground colors.
struct TransparentWindow: NSViewRepresentable {
    let theme: ThemeChoice

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

        switch theme {
        case .system: window.appearance = nil
        case .light:  window.appearance = NSAppearance(named: .aqua)
        case .dark:   window.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func hideEffectViews(_ view: NSView?) {
        guard let view else { return }
        for sub in view.subviews {
            if sub is NSVisualEffectView { sub.isHidden = true }
            hideEffectViews(sub)
        }
    }
}

/// Forces the hosting NSWindow's `appearance` to match `theme`. SwiftUI's
/// `.preferredColorScheme(nil)` does not reliably reset `window.appearance`
/// back to nil after it has previously been pinned to .light or .dark, so the
/// Settings window can stay stuck on the old theme when the user switches
/// back to "System". Setting `window.appearance` directly is the only way to
/// undo the override.
struct WindowAppearanceBinder: NSViewRepresentable {
    let theme: ThemeChoice

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.setAccessibilityHidden(true)
        DispatchQueue.main.async { apply(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(nsView.window) }
    }

    private func apply(_ window: NSWindow?) {
        guard let window else { return }
        switch theme {
        case .system: window.appearance = nil
        case .light:  window.appearance = NSAppearance(named: .aqua)
        case .dark:   window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
