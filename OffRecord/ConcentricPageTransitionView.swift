//
//  ConcentricPageTransitionView.swift
//  OffRecord
//
//  App-scoped concentric page reveal adapted from the ConcentricOnboarding sample.
//

import SwiftUI

private enum ConcentricPageDirection {
    case forward
    case backward
}

private enum ConcentricAnimationStage {
    case idle
    case growing
    case shrinking
}

private final class ConcentricActionGate: ObservableObject {
    @Published var isLocked = false
}

struct ConcentricPageTransitionView<Content: View>: View {
    typealias PageContent = (view: Content, background: Color)

    let pages: [PageContent]
    @Binding var currentIndex: Int
    var duration: Double = 0.8
    let ctaTitle: String
    let ctaIcon: String?
    let isCTADisabled: Bool
    let secondaryTitle: String?
    let playsPrimaryHaptic: Bool
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var actionGate = ConcentricActionGate()

    @State private var displayedIndex: Int
    @State private var incomingIndex: Int
    @State private var progress: Double = 0
    @State private var direction: ConcentricPageDirection = .forward
    @State private var animationStage: ConcentricAnimationStage = .idle
    @State private var isAnimating = false
    @State private var backgroundColor: Color
    @State private var circleColor: Color
    @State private var keyboardHeight: CGFloat = 0

    private let radius: Double = 30
    private let limit: Double = 15

    private var inAnimation: Animation { .easeIn(duration: duration / 2) }
    private var outAnimation: Animation { .easeOut(duration: duration / 2) }
    private var fullAnimation: Animation { .easeInOut(duration: duration) }

    init(
        pages: [PageContent],
        currentIndex: Binding<Int>,
        duration: Double = 0.8,
        ctaTitle: String,
        ctaIcon: String? = nil,
        isCTADisabled: Bool = false,
        secondaryTitle: String? = nil,
        playsPrimaryHaptic: Bool = true,
        onPrimaryAction: @escaping () -> Void,
        onSecondaryAction: @escaping () -> Void = { }
    ) {
        self.pages = pages
        self._currentIndex = currentIndex
        self.duration = duration
        self.ctaTitle = ctaTitle
        self.ctaIcon = ctaIcon
        self.isCTADisabled = isCTADisabled
        self.secondaryTitle = secondaryTitle
        self.playsPrimaryHaptic = playsPrimaryHaptic
        self.onPrimaryAction = onPrimaryAction
        self.onSecondaryAction = onSecondaryAction

        let safeIndex = pages.indices.contains(currentIndex.wrappedValue) ? currentIndex.wrappedValue : 0
        let nextIndex = pages.indices.contains(safeIndex + 1) ? safeIndex + 1 : safeIndex
        self._displayedIndex = State(initialValue: safeIndex)
        self._incomingIndex = State(initialValue: nextIndex)
        self._backgroundColor = State(initialValue: pages.indices.contains(safeIndex) ? pages[safeIndex].background : .clear)
        let initialCircleColor: Color
        if safeIndex == pages.count - 1 {
            initialCircleColor = OffRecordColor.brandPlum
        } else {
            initialCircleColor = pages.indices.contains(nextIndex) ? pages[nextIndex].background : .clear
        }
        self._circleColor = State(initialValue: initialCircleColor)
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomPad = max(28, proxy.safeAreaInsets.bottom + 18)
            let buttonCenterY = proxy.size.height - bottomPad - radius

            ZStack {
                backgroundColor
                    .ignoresSafeArea([.container, .keyboard])

                if pages.indices.contains(displayedIndex) {
                    pages[displayedIndex].view
                        .id(displayedIndex)
                        .scaleEffect(isAnimating ? 2 / 3 : 1)
                        .offset(
                            x: isAnimating ? outgoingOffset(in: proxy.size) : 0,
                            y: isAnimating ? 40 : 0
                        )
                        .allowsHitTesting(!isAnimating)
                        .animation(isAnimating ? fullAnimation : .none, value: isAnimating)
                }

                if pages.indices.contains(incomingIndex), incomingIndex != displayedIndex {
                    pages[incomingIndex].view
                        .id(incomingIndex)
                        .scaleEffect(isAnimating ? 1 : 2 / 3)
                        .offset(
                            x: isAnimating ? 0 : incomingOffset(in: proxy.size),
                            y: isAnimating ? 0 : 40
                        )
                        .allowsHitTesting(false)
                        .animation(isAnimating ? fullAnimation : .none, value: isAnimating)
                }

                ConcentricRevealShape(
                    progress: progress,
                    radius: radius,
                    limit: limit,
                    direction: direction,
                    buttonCenterY: buttonCenterY
                )
                .fill(circleColor)
                .opacity(isAnimating ? 1 : 0)
                .allowsHitTesting(false)
                .onAnimationCompleted(for: progress) {
                    animationCompleted()
                }
            }
            .overlay(alignment: .bottom) {
                bottomControls(bottomInset: proxy.safeAreaInsets.bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea([.container, .keyboard])
        .onAppear {
            syncToCurrentIndex(animated: false)
        }
        .onChange(of: currentIndex) { _, _ in
            syncToCurrentIndex(animated: !reduceMotion)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    private func syncToCurrentIndex(animated: Bool) {
        guard pages.indices.contains(currentIndex), currentIndex != displayedIndex else { return }

        if !animated {
            displayedIndex = currentIndex
            incomingIndex = nextIndex(after: currentIndex)
            backgroundColor = pages[currentIndex].background
            circleColor = pages[incomingIndex].background
            applyLastPageCircleOverride()
            progress = 0
            animationStage = .idle
            isAnimating = false
            return
        }

        direction = currentIndex > displayedIndex ? .forward : .backward
        incomingIndex = currentIndex
        isAnimating = true
        animationStage = .growing
        backgroundColor = pages[displayedIndex].background
        circleColor = pages[incomingIndex].background
        progress = 0

        withAnimation(inAnimation) {
            progress = limit
        }
        scheduleAnimationFallback(for: .growing)
    }

    private func animationCompleted() {
        advanceAnimationStageIfNeeded()
    }

    private func advanceAnimationStageIfNeeded() {
        switch animationStage {
        case .idle:
            return
        case .growing:
            animationStage = .shrinking
            progress = limit + 0.001
            backgroundColor = pages.indices.contains(incomingIndex) ? pages[incomingIndex].background : backgroundColor
            circleColor = pages.indices.contains(displayedIndex) ? pages[displayedIndex].background : circleColor
            withAnimation(outAnimation) {
                progress = 2 * limit
            }
            scheduleAnimationFallback(for: .shrinking)
        case .shrinking:
            animationStage = .idle
            displayedIndex = incomingIndex
            incomingIndex = nextIndex(after: displayedIndex)
            isAnimating = false
            progress = 0
            backgroundColor = pages.indices.contains(displayedIndex) ? pages[displayedIndex].background : backgroundColor
            circleColor = pages.indices.contains(incomingIndex) ? pages[incomingIndex].background : circleColor
            applyLastPageCircleOverride()
        }
    }

    private func scheduleAnimationFallback(for stage: ConcentricAnimationStage) {
        let delay = max(0.05, duration / 2 + 0.08)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isAnimating, animationStage == stage else { return }
            advanceAnimationStageIfNeeded()
        }
    }

    private func nextIndex(after index: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return index + 1 < pages.count ? index + 1 : index
    }

    private func applyLastPageCircleOverride() {
        if displayedIndex == pages.count - 1 {
            circleColor = OffRecordColor.brandPlum
        }
    }

    private func outgoingOffset(in size: CGSize) -> CGFloat {
        direction == .forward ? -size.width : size.width
    }

    private func incomingOffset(in size: CGSize) -> CGFloat {
        direction == .forward ? size.width : -size.width
    }

    private func bottomControls(bottomInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            ConcentricCircleButton(
                icon: ctaIcon ?? "chevron.forward",
                circleColor: effectiveCircleColor,
                foregroundColor: backgroundColor,
                isDisabled: isAnimating || isCTADisabled || actionGate.isLocked,
                isAnimating: isAnimating,
                action: triggerPrimaryAction
            )

            if let secondaryTitle {
                Button(secondaryTitle, action: triggerSecondaryAction)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textBrand.opacity(0.78))
                    .buttonStyle(.plain)
                    .disabled(isAnimating || actionGate.isLocked)
                    .opacity(isAnimating || actionGate.isLocked ? 0.55 : 1)
                    .frame(minHeight: 32)
            }
        }
        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - bottomInset + 12 : max(28, bottomInset + 18))
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
    }

    private var effectiveCircleColor: Color {
        if displayedIndex == pages.count - 1 {
            return OffRecordColor.brandPlum
        }
        return circleColor
    }

    private func triggerPrimaryAction() {
        guard !isAnimating, !isCTADisabled, !actionGate.isLocked else { return }
        actionGate.isLocked = true
        if playsPrimaryHaptic {
            HapticManager.shared.buttonTap()
        }
        onPrimaryAction()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            actionGate.isLocked = false
        }
    }

    private func triggerSecondaryAction() {
        guard !isAnimating, !actionGate.isLocked else { return }
        HapticManager.shared.buttonTap()
        onSecondaryAction()
    }
}

private struct ConcentricCircleButton: View {
    let icon: String
    let circleColor: Color
    let foregroundColor: Color
    let isDisabled: Bool
    let isAnimating: Bool
    let action: () -> Void

    private let size: CGFloat = 60
    @State private var glowPulse = false

    private var isGlowActive: Bool { !isDisabled && !isAnimating }

    private var iconColor: Color {
        foregroundColor == circleColor ? OffRecordColor.textBrand : foregroundColor
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isDisabled ? circleColor.opacity(0.35) : circleColor)
                    .frame(width: size, height: size)
                    .shadow(
                        color: .black.opacity(isDisabled ? 0 : 0.22),
                        radius: 14,
                        x: 0,
                        y: 6
                    )
                    .overlay(
                        Circle()
                            .stroke(circleColor.opacity(isGlowActive ? 0.5 : 0), lineWidth: 3)
                            .frame(width: size + 10, height: size + 10)
                            .scaleEffect(glowPulse ? 1.18 : 1.0)
                            .opacity(glowPulse ? 0.0 : 0.7)
                            .animation(
                                isGlowActive
                                    ? .easeInOut(duration: 1.5).repeatForever(autoreverses: false)
                                    : .default,
                                value: glowPulse
                            )
                    )
                    .shadow(
                        color: circleColor.opacity(isGlowActive ? 0.45 : 0),
                        radius: isGlowActive ? 16 : 0,
                        x: 0, y: 0
                    )
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isAnimating ? 0 : (isDisabled ? 0.55 : 1))
        .animation(.easeInOut(duration: 0.15), value: isAnimating)
        .accessibilityLabel("Next")
        .accessibilityIdentifier("onboarding.primaryCTA")
        .onAppear { glowPulse = true }
        .onChange(of: isGlowActive) { _, active in
            glowPulse = active
        }
    }
}

private struct ConcentricRevealShape: Shape {
    var progress: Double
    let radius: Double
    let limit: Double
    let direction: ConcentricPageDirection
    let buttonCenterY: CGFloat

    var animatableData: CGFloat {
        get { CGFloat(progress) }
        set { progress = Double(newValue) }
    }

    func path(in rect: CGRect) -> Path {
        let local = localValues()
        let localProgress = local.progress
        let circleRadius: CGFloat
        let delta: CGFloat
        let center: CGPoint

        if local.type == .growing {
            circleRadius = CGFloat(radius + pow(2, localProgress))
            delta = CGFloat((1 - localProgress / limit) * radius)
            center = CGPoint(
                x: rect.midX + circleRadius - delta - 2,
                y: buttonCenterY
            )
        } else {
            circleRadius = CGFloat(radius + pow(2, limit - localProgress))
            delta = CGFloat((localProgress / limit) * radius)
            center = CGPoint(
                x: rect.midX - circleRadius + delta,
                y: buttonCenterY
            )
        }

        let circleRect = CGRect(
            x: center.x - circleRadius,
            y: center.y - circleRadius,
            width: 2 * circleRadius,
            height: 2 * circleRadius
        )
        return Circle().path(in: circleRect)
    }

    private func localValues() -> (type: AnimationType, progress: Double) {
        if direction == .forward {
            if progress <= limit {
                return (.growing, progress)
            } else if progress <= 2 * limit {
                return (.shrinking, progress - limit)
            } else {
                return (.growing, 0)
            }
        } else {
            if progress <= limit {
                return (.shrinking, limit - progress)
            } else if progress <= 2 * limit {
                return (.growing, 2 * limit - progress)
            } else {
                return (.shrinking, 0)
            }
        }
    }

    private enum AnimationType {
        case growing
        case shrinking
    }
}

private struct AnimationCompletionObserverModifier<Value: VectorArithmetic>: AnimatableModifier {
    var animatableData: Value {
        didSet { notifyCompletion() }
    }

    private let targetValue: Value
    private let completion: () -> Void

    init(observedValue: Value, completion: @escaping () -> Void) {
        self.animatableData = observedValue
        self.targetValue = observedValue
        self.completion = completion
    }

    func body(content: Content) -> some View {
        content
    }

    private func notifyCompletion() {
        let difference = animatableData - targetValue
        if difference.magnitudeSquared < 0.0001 {
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

private extension View {
    func onAnimationCompleted<Value: VectorArithmetic>(
        for value: Value,
        completion: @escaping () -> Void
    ) -> ModifiedContent<Self, AnimationCompletionObserverModifier<Value>> {
        modifier(AnimationCompletionObserverModifier(observedValue: value, completion: completion))
    }
}
