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

struct ConcentricPageTransitionView<Content: View>: View {
    typealias PageContent = (view: Content, background: Color)

    let pages: [PageContent]
    @Binding var currentIndex: Int
    var duration: Double = 0.8
    let ctaTitle: String
    let ctaIcon: String?
    let isCTADisabled: Bool
    let secondaryTitle: String?
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedIndex: Int
    @State private var incomingIndex: Int
    @State private var progress: Double = 0
    @State private var direction: ConcentricPageDirection = .forward
    @State private var isAnimating = false
    @State private var backgroundColor: Color
    @State private var circleColor: Color

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
        self.onPrimaryAction = onPrimaryAction
        self.onSecondaryAction = onSecondaryAction

        let safeIndex = pages.indices.contains(currentIndex.wrappedValue) ? currentIndex.wrappedValue : 0
        let nextIndex = pages.indices.contains(safeIndex + 1) ? safeIndex + 1 : safeIndex
        self._displayedIndex = State(initialValue: safeIndex)
        self._incomingIndex = State(initialValue: nextIndex)
        self._backgroundColor = State(initialValue: pages.indices.contains(safeIndex) ? pages[safeIndex].background : .clear)
        self._circleColor = State(initialValue: pages.indices.contains(nextIndex) ? pages[nextIndex].background : .clear)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                if pages.indices.contains(displayedIndex) {
                    pages[displayedIndex].view
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
                    direction: direction
                )
                .fill(circleColor)
                .allowsHitTesting(false)
                .onAnimationCompleted(for: progress) {
                    animationCompleted()
                }
            }
            .overlay(alignment: .bottom) {
                bottomControls
                    .padding(.bottom, 52)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            syncToCurrentIndex(animated: false)
        }
        .onChange(of: currentIndex) { _, _ in
            syncToCurrentIndex(animated: !reduceMotion)
        }
    }

    private func syncToCurrentIndex(animated: Bool) {
        guard pages.indices.contains(currentIndex), currentIndex != displayedIndex else { return }

        if !animated {
            displayedIndex = currentIndex
            incomingIndex = nextIndex(after: currentIndex)
            backgroundColor = pages[currentIndex].background
            circleColor = pages[incomingIndex].background
            progress = 0
            isAnimating = false
            return
        }

        direction = currentIndex > displayedIndex ? .forward : .backward
        incomingIndex = currentIndex
        isAnimating = true
        backgroundColor = pages[displayedIndex].background
        circleColor = pages[incomingIndex].background
        progress = 0

        withAnimation(inAnimation) {
            progress = limit
        }
    }

    private func animationCompleted() {
        if progress == limit {
            progress += 0.001
            backgroundColor = pages.indices.contains(incomingIndex) ? pages[incomingIndex].background : backgroundColor
            circleColor = pages.indices.contains(displayedIndex) ? pages[displayedIndex].background : circleColor
            withAnimation(outAnimation) {
                progress = 2 * limit
            }
        } else if progress == 2 * limit {
            displayedIndex = incomingIndex
            incomingIndex = nextIndex(after: displayedIndex)
            isAnimating = false
            progress = 0
            backgroundColor = pages.indices.contains(displayedIndex) ? pages[displayedIndex].background : backgroundColor
            circleColor = pages.indices.contains(incomingIndex) ? pages[incomingIndex].background : circleColor
        }
    }

    private func nextIndex(after index: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return index + 1 < pages.count ? index + 1 : index
    }

    private func outgoingOffset(in size: CGSize) -> CGFloat {
        direction == .forward ? -size.width : size.width
    }

    private func incomingOffset(in size: CGSize) -> CGFloat {
        direction == .forward ? size.width : -size.width
    }

    private var isTerminalPage: Bool {
        guard let lastIndex = pages.indices.last else { return false }
        return displayedIndex == lastIndex && incomingIndex == displayedIndex
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if let secondaryTitle {
                Button(secondaryTitle, action: onSecondaryAction)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textBrand.opacity(0.78))
                    .buttonStyle(.plain)
                    .disabled(isAnimating)
                    .opacity(isAnimating ? 0.55 : 1)
            }

            if isTerminalPage {
                terminalPrimaryButton
            } else {
                primaryButton
            }
        }
    }

    private var primaryButton: some View {
        Button(action: onPrimaryAction) {
            ZStack {
                Circle()
                    .fill(isAnimating ? .clear : circleColor)
                    .frame(width: 2 * radius, height: 2 * radius)
                Image(systemName: ctaIcon ?? "chevron.forward")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(OffRecordColor.textBrand)
            }
            .frame(width: 2 * radius, height: 2 * radius)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isAnimating || isCTADisabled)
        .opacity(isCTADisabled ? 0.42 : 1)
        .accessibilityLabel(ctaTitle)
    }

    private var terminalPrimaryButton: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: 8) {
                Text(ctaTitle)
                if let ctaIcon {
                    Image(systemName: ctaIcon)
                }
            }
            .font(OffRecordTypography.sectionTitle)
            .foregroundStyle(OffRecordColor.textBrand)
            .frame(maxWidth: 360)
            .padding(.horizontal, 22)
            .padding(.vertical, 17)
            .background(OffRecordColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isAnimating || isCTADisabled)
        .opacity(isCTADisabled ? 0.42 : 1)
        .padding(.horizontal, 28)
        .accessibilityLabel(ctaTitle)
    }
}

private struct ConcentricRevealShape: Shape {
    var progress: Double
    let radius: Double
    let limit: Double
    let direction: ConcentricPageDirection

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
                y: rect.maxY - 82
            )
        } else {
            circleRadius = CGFloat(radius + pow(2, limit - localProgress))
            delta = CGFloat((localProgress / limit) * radius)
            center = CGPoint(
                x: rect.midX - circleRadius + delta,
                y: rect.maxY - 82
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
        if animatableData == targetValue {
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
