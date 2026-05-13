import SwiftUI

struct MoodDialPointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let baseWidth: CGFloat = 50
        let baseHeight: CGFloat = 136
        let scale = min(rect.width / baseWidth, rect.height / baseHeight)
        let origin = CGPoint(
            x: rect.midX - baseWidth * scale / 2,
            y: rect.midY - baseHeight * scale / 2
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()

        path.move(to: point(25, 136))
        path.addCurve(
            to: point(8.9, 82),
            control1: point(18.1, 133.4),
            control2: point(9.4, 111.2)
        )
        path.addCurve(
            to: point(10.8, 29),
            control1: point(6.9, 60.5),
            control2: point(7.3, 42)
        )
        path.addCurve(
            to: point(25, 2),
            control1: point(14.8, 10.4),
            control2: point(18.8, 2)
        )
        path.addCurve(
            to: point(39.2, 29),
            control1: point(31.2, 2),
            control2: point(35.2, 10.4)
        )
        path.addCurve(
            to: point(41.1, 82),
            control1: point(42.7, 42),
            control2: point(43.1, 60.5)
        )
        path.addCurve(
            to: point(25, 136),
            control1: point(40.6, 111.2),
            control2: point(31.9, 133.4)
        )
        path.closeSubpath()
        return path
    }
}
