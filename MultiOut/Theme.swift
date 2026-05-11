import SwiftUI

extension Color {
    static let chassis    = Color(red: 0.073, green: 0.071, blue: 0.078)
    static let armed      = Color(red: 1.00,  green: 0.62,  blue: 0.20)
    static let armedDim   = Color(red: 0.78,  green: 0.46,  blue: 0.13)
    static let signal     = Color(red: 0.42,  green: 0.88,  blue: 0.55)
    static let danger     = Color(red: 0.95,  green: 0.32,  blue: 0.30)
    static let hairline   = Color.white.opacity(0.07)
    static let textHi     = Color(white: 0.95)
    static let textMid    = Color(white: 0.55)
    static let textLo     = Color(white: 0.32)
}

func sectionLabel(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(1.5)
        .foregroundStyle(Color.textLo)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
}

func hairlineDivider() -> some View {
    Rectangle().fill(Color.hairline).frame(height: 0.5)
}
