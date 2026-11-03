//
//  ConcentricOnboardingPage.swift
//  OffRecord
//
//  The frame around each onboarding step: the progress header pinned to the
//  top, and the scrolling page that makes room for the keyboard and keeps
//  the focused field in view.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ConcentricOnboardingScreen<Content: View>: View {
    let step: OnboardingStep
    let isIPad: Bool
    let isHeaderCompact: Bool
    let isHeaderLifted: Bool
    let headerLiftOffset: CGFloat
    let onBack: () -> Void
    let content: Content

    init(
        step: OnboardingStep,
        isIPad: Bool,
        isHeaderCompact: Bool,
        isHeaderLifted: Bool,
        headerLiftOffset: CGFloat,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.isIPad = isIPad
        self.isHeaderCompact = isHeaderCompact
        self.isHeaderLifted = isHeaderLifted
        self.headerLiftOffset = headerLiftOffset
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            content

            OnboardingProgressHeader(
                step: step,
                canGoBack: step.canGoBack,
                isCompact: isHeaderCompact,
                onBack: onBack
            )
            .padding(.horizontal, isIPad ? 44 : 20)
            .padding(.top, headerTopPadding)
            .offset(y: isHeaderLifted ? headerLiftOffset : 0)
            .animation(.easeInOut(duration: 0.25), value: isHeaderLifted)
            .animation(.easeInOut(duration: 0.25), value: isHeaderCompact)
        }
    }

    private var headerTopPadding: CGFloat {
        max(14, currentWindowSafeAreaTop + 8)
    }

    private var currentWindowSafeAreaTop: CGFloat {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
        #else
        0
        #endif
    }
}

struct ConcentricOnboardingPage<Content: View>: View {
    let isIPad: Bool
    let isKeyboardAdaptive: Bool
    let scrollTargetID: String?
    let onTextInputFocusChange: ((Bool) -> Void)?
    let content: Content
    @State private var isTextInputFocused = false

    init(
        isIPad: Bool,
        isKeyboardAdaptive: Bool = false,
        scrollTargetID: String? = nil,
        onTextInputFocusChange: ((Bool) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isIPad = isIPad
        self.isKeyboardAdaptive = isKeyboardAdaptive
        self.scrollTargetID = scrollTargetID
        self.onTextInputFocusChange = onTextInputFocusChange
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack {
                        Spacer(minLength: 0)

                        content
                            .frame(maxWidth: isIPad ? 620 : .infinity)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: minContentHeight(for: proxy.size.height))
                    .padding(.horizontal, isIPad ? 44 : 24)
                    .padding(.top, contentTopPadding)
                    .padding(.bottom, contentBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .animation(.easeInOut(duration: 0.25), value: isTextInputFocused)
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
                    setTextInputFocused(true)
                }
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
                    setTextInputFocused(false)
                }
                .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in
                    setTextInputFocused(true)
                }
                .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in
                    setTextInputFocused(false)
                }
                .onChange(of: isTextInputFocused) { _, isFocused in
                    guard isKeyboardAdaptive, isFocused, let scrollTargetID else { return }
                    DispatchQueue.main.async {
                        withOffRecordAnimation(OffRecordMotion.snappy) {
                            scrollProxy.scrollTo(scrollTargetID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func setTextInputFocused(_ isFocused: Bool) {
        guard isKeyboardAdaptive else { return }
        isTextInputFocused = isFocused
        onTextInputFocusChange?(isFocused)
    }

    private var contentTopPadding: CGFloat {
        isFocusActive ? (isIPad ? 126 : 118) : (isIPad ? 164 : 150)
    }

    private var contentBottomPadding: CGFloat {
        let baseBottomPadding: CGFloat = 164
        guard isFocusActive else { return baseBottomPadding }
        return baseBottomPadding + (isIPad ? 250 : 300)
    }

    private func minContentHeight(for availableHeight: CGFloat) -> CGFloat {
        if isFocusActive {
            return max(availableHeight - 120, 420)
        }
        return max(availableHeight - 250, 520)
    }

    private var isFocusActive: Bool {
        isKeyboardAdaptive && isTextInputFocused
    }
}

private struct OnboardingProgressHeader: View {
    let step: OnboardingStep
    let canGoBack: Bool
    let isCompact: Bool
    let onBack: () -> Void
    private let sideWidth: CGFloat = 54

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(OffRecordTypography.sectionTitle)
                        .frame(width: 36, height: 36)
                        .background(canGoBack ? OnboardingPalette.surfaceSubtle : OnboardingPalette.surfaceBarelyVisible)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0)
                .frame(width: sideWidth, alignment: .leading)

                headerCenterContent
                    .frame(maxWidth: .infinity)

                Text(step.progressText)
                    .font(OffRecordTypography.badgeLabel)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                    .frame(width: sideWidth, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.black.opacity(0.14))
                    Capsule()
                        .fill(OnboardingPalette.foreground)
                        .frame(width: max(8, proxy.size.width * step.progress))
                }
            }
            .frame(height: 6)
        }
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [step.backgroundColor, step.backgroundColor.opacity(0.96), step.backgroundColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private var headerCenterContent: some View {
        Text(step.pageTitle)
            .font(isCompact ? OffRecordTypography.titleMedium : OffRecordTypography.screenTitle)
            .foregroundStyle(OnboardingPalette.foreground)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
    }
}
