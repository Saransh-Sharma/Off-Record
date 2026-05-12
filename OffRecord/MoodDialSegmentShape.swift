import SwiftUI

struct MoodDialSegmentShape: Shape {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngleDegrees: Double
    let endAngleDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outerPoints = points(radius: outerRadius, from: startAngleDegrees, to: endAngleDegrees)
        let innerPoints = points(radius: innerRadius, from: endAngleDegrees, to: startAngleDegrees)

        guard let first = outerPoints.first else { return path }
        path.move(to: first)
        outerPoints.dropFirst().forEach { path.addLine(to: $0) }
        innerPoints.forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func points(radius: CGFloat, from startAngle: Double, to endAngle: Double) -> [CGPoint] {
        let steps = max(6, Int(abs(endAngle - startAngle) / 2))
        return (0...steps).map { step in
            let progress = Double(step) / Double(steps)
            let angle = startAngle + (endAngle - startAngle) * progress
            let radians = angle * .pi / 180
            return CGPoint(
                x: center.x + CGFloat(cos(radians)) * radius,
                y: center.y + CGFloat(sin(radians)) * radius
            )
        }
    }
}
