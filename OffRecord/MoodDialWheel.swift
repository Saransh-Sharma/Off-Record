import SwiftUI

struct MoodDialWheel: View {
    @Binding var selectedMood: Mood
    let metrics: MoodDialWheelMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rotationDegrees = 0.0
    @State private var dragStartRotationDegrees = 0.0
    @State private var dragStartAngleDegrees: Double?
    @State private var pointerBounce = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            dialSegments(metrics: metrics)
                .rotationEffect(
                    .degrees(rotationDegrees),
                    anchor: UnitPoint(
                        x: metrics.center.x / max(metrics.size.width, 1),
                        y: metrics.center.y / max(metrics.size.height, 1)
                    )
                )
                .animation(isDragging || reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78), value: rotationDegrees)
                .zIndex(1)

            MoodDialPointer()
                .position(x: metrics.center.x, y: metrics.pointerCenterY + (pointerBounce ? -5 : 0))
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62), value: pointerBounce)
                .zIndex(2)

            Color.clear
                .frame(width: metrics.size.width, height: metrics.gestureHeight)
                .contentShape(Rectangle())
                .position(x: metrics.center.x, y: metrics.gestureCenterY)
                .gesture(dragGesture(center: metrics.center))
                .zIndex(3)
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .accessibilityElement()
        .accessibilityLabel("Mood dial")
        .accessibilityValue(selectedMood.displayName)
        .accessibilityHint("Swipe up or down to change mood.")
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
        .accessibilityIdentifier("moodDial.wheel")
        .onAppear {
            rotationDegrees = MoodDialMath.rotationDegrees(for: selectedMood)
        }
    }

    private func dialSegments(metrics: MoodDialWheelMetrics) -> some View {
        ZStack {
            ForEach(Array(Mood.dialMoods.enumerated()), id: \.element.id) { index, mood in
                let isSelected = mood == selectedMood
                let sweep = MoodDialMath.segmentSweepDegrees()
                let gap = 0.0
                let startAngle = MoodDialMath.arcStartDegrees + Double(index) * sweep + gap / 2
                let endAngle = MoodDialMath.arcStartDegrees + Double(index + 1) * sweep - gap / 2
                let outerRadius = metrics.outerRadius + (isSelected ? 10 : 0)
                let segmentShape = MoodDialSegmentShape(
                    center: metrics.center,
                    innerRadius: metrics.innerRadius,
                    outerRadius: outerRadius,
                    startAngleDegrees: startAngle,
                    endAngleDegrees: endAngle
                )

                segmentShape
                    .fill(mood.dialSegmentColor.opacity(isSelected ? 1 : 0.78))
                .overlay(
                    segmentShape
                        .fill(Color.white.opacity(isSelected ? 0.08 : 0))
                        .blendMode(.softLight)
                )

                Image(mood.dialFaceAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isSelected ? 48 : 42, height: isSelected ? 48 : 42)
                    .rotationEffect(.degrees(iconPreRotationDegrees(for: index)))
                    .opacity(isSelected ? 0.88 : 0.56)
                    .position(iconPosition(for: index, metrics: metrics))
                    .accessibilityHidden(true)
            }
        }
    }

    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragStartAngleDegrees == nil {
                    isDragging = true
                    dragStartAngleDegrees = MoodDialMath.angleDegrees(for: value.startLocation, around: center)
                    dragStartRotationDegrees = rotationDegrees
                }

                let startAngle = dragStartAngleDegrees ?? MoodDialMath.angleDegrees(for: value.startLocation, around: center)
                let currentAngle = MoodDialMath.angleDegrees(for: value.location, around: center)
                let delta = MoodDialMath.normalizedDeltaDegrees(from: startAngle, to: currentAngle)
                let nextRotation = MoodDialMath.resistedRotationDegrees(dragStartRotationDegrees + delta)
                updateSelection(forRotation: nextRotation, animated: false)
            }
            .onEnded { _ in
                dragStartAngleDegrees = nil
                isDragging = false
                snapToCurrentMood()
            }
    }

    private func updateSelection(forRotation nextRotation: Double, animated: Bool) {
        let nextMood = MoodDialMath.mood(forRotationDegrees: nextRotation)
        let apply = {
            rotationDegrees = nextRotation
            if nextMood != selectedMood {
                selectedMood = nextMood
                HapticManager.shared.selectionChanged()
            }
        }

        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func snapToCurrentMood() {
        let nearestIndex = MoodDialMath.nearestIndex(forRotationDegrees: rotationDegrees)
        let snappedRotation = MoodDialMath.rotationDegrees(for: nearestIndex)
        selectedMood = Mood.dialMoods[nearestIndex]
        updateSelection(forRotation: snappedRotation, animated: true)
        bouncePointer()
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let currentIndex = MoodDialMath.index(for: selectedMood)
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(currentIndex + 1, Mood.dialMoods.count - 1)
        case .decrement:
            nextIndex = max(currentIndex - 1, 0)
        @unknown default:
            return
        }

        selectedMood = Mood.dialMoods[nextIndex]
        updateSelection(forRotation: MoodDialMath.rotationDegrees(for: nextIndex), animated: true)
        bouncePointer()
    }

    private func bouncePointer() {
        guard !reduceMotion else { return }
        pointerBounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pointerBounce = false
        }
    }

    private func iconPosition(for index: Int, metrics: MoodDialWheelMetrics) -> CGPoint {
        let angle = MoodDialMath.centerAngleDegrees(for: index)
        let radians = angle * .pi / 180
        let radius = (metrics.innerRadius + metrics.outerRadius) / 2
        return CGPoint(
            x: metrics.center.x + CGFloat(cos(radians)) * radius,
            y: metrics.center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func iconPreRotationDegrees(for index: Int) -> Double {
        MoodDialMath.centerAngleDegrees(for: index) - MoodDialMath.pointerAngleDegrees
    }
}
