import SwiftUI
import AppKit

private struct TuttiBroadcastShape: View {
    var level: Int
    var size: CGFloat

    var body: some View {
        Canvas { context, _ in
            let unit = size / 22.0
            let stroke = 1.8 * unit
            let style = StrokeStyle(lineWidth: stroke, lineCap: .round)

            let cx = size / 2 - 12 * unit
            let cy = size / 2 - 12 * unit
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cx + x * unit, y: cy + y * unit)
            }

            let dot = Path(ellipseIn: CGRect(
                x: cx + (12 - 2.6) * unit,
                y: cy + (12 - 2.6) * unit,
                width: 5.2 * unit,
                height: 5.2 * unit
            ))
            context.fill(dot, with: .color(.black))

            if level >= 1 {
                var innerLeft = Path()
                innerLeft.addArc(
                    center: pt(10.571, 12),
                    radius: 5 * unit,
                    startAngle: .degrees(135.6),
                    endAngle: .degrees(224.4),
                    clockwise: false
                )
                context.stroke(innerLeft, with: .color(.black), style: style)

                var innerRight = Path()
                innerRight.addArc(
                    center: pt(13.429, 12),
                    radius: 5 * unit,
                    startAngle: .degrees(-44.4),
                    endAngle: .degrees(44.4),
                    clockwise: false
                )
                context.stroke(innerRight, with: .color(.black), style: style)
            }

            if level >= 2 {
                var outerLeft = Path()
                outerLeft.addArc(
                    center: pt(10.021, 12),
                    radius: 8.5 * unit,
                    startAngle: .degrees(135.1),
                    endAngle: .degrees(224.9),
                    clockwise: false
                )
                context.stroke(outerLeft, with: .color(.black), style: style)

                var outerRight = Path()
                outerRight.addArc(
                    center: pt(13.979, 12),
                    radius: 8.5 * unit,
                    startAngle: .degrees(-44.9),
                    endAngle: .degrees(44.9),
                    clockwise: false
                )
                context.stroke(outerRight, with: .color(.black), style: style)
            }
        }
        .frame(width: size, height: size)
    }
}

enum TuttiPulseIcon {
    @MainActor
    static func image(level: Int, size: CGFloat = 22) -> NSImage {
        let view = TuttiBroadcastShape(level: level, size: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        return image
    }
}
