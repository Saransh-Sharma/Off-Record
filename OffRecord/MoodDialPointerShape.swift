import SwiftUI

struct MoodDialPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let baseWidth: CGFloat = 48
        let baseHeight: CGFloat = 108
        let scale = min(rect.width / baseWidth, rect.height / baseHeight)
        let origin = CGPoint(
            x: rect.midX - baseWidth * scale / 2,
            y: rect.midY - baseHeight * scale / 2
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()

        path.move(to: point(24, 108))
        path.addCurve(
            to: point(8.2, 66),
            control1: point(17.4, 106.1),
            control2: point(8.8, 90.2)
        )
        path.addCurve(
            to: point(9.8, 25),
            control1: point(6.4, 50.2),
            control2: point(6.8, 36.6)
        )
        path.addCurve(
            to: point(24, 1.8),
            control1: point(13.2, 9.2),
            control2: point(17.5, 1.8)
        )
        path.addCurve(
            to: point(38.2, 25),
            control1: point(30.5, 1.8),
            control2: point(34.8, 9.2)
        )
        path.addCurve(
            to: point(39.8, 66),
            control1: point(41.2, 36.6),
            control2: point(41.6, 50.2)
        )
        path.addCurve(
            to: point(24, 108),
            control1: point(39.2, 90.2),
            control2: point(30.6, 106.1)
        )
        path.closeSubpath()
        return path
    }
}
