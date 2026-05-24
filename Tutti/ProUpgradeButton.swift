import SwiftUI
import AppKit

/// Pill-shaped CTA that opens the purchase URL. Used wherever a free /
/// expired-trial user would otherwise have hit a Pro-only control.
struct ProUpgradeButton: View {
    let purchaseURL: URL
    var label: LocalizedStringKey = "解锁 Pro · $7.99"

    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(purchaseURL)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.designAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .stroke(Color.designAccent.opacity(hovering ? 0.9 : 0.6), lineWidth: 1)
                    .background(Capsule().fill(Color.designAccent.opacity(hovering ? 0.12 : 0.06)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
