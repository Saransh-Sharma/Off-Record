//
//  OnboardingView.swift
//  OffRecord
//
//  Privacy-focused onboarding experience
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage = 0

    private var isIPad: Bool { horizontalSizeClass == .regular }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "brain.head.profile",
            iconColor: .teal,
            title: "Meet OffRecord AI Journal",
            subtitle: "The only AI that truly knows you",
            description: "Not just another diary. OffRecord AI Journal remembers your life — your dreams, struggles, the people you love, and what makes you, you.",
            background: Color(red: 5/255, green: 8/255, blue: 22/255),
            textColor: .white
        ),
        OnboardingPage(
            icon: "person.crop.circle.fill",
            iconColor: .pink,
            title: "Meet Your Digital Twin",
            subtitle: "A mirror of your inner world",
            description: "Your Digital Twin learns your personality, emotional patterns, and the people and topics in your life. Watch it grow as you journal.",
            background: Color(red: 76/255, green: 36/255, blue: 90/255),
            textColor: .white
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            iconColor: .orange,
            title: "Insights That Matter",
            subtitle: "Understand yourself better",
            description: "Track mood trends, writing streaks, and emotional patterns. See your personal knowledge graph grow with the people, places, and topics in your life.",
            background: Color(red: 92/255, green: 51/255, blue: 63/255),
            textColor: .white
        ),
        OnboardingPage(
            icon: "lock.shield",
            iconColor: .mint,
            title: "100% Private. Always.",
            subtitle: "Your innermost thoughts stay yours",
            description: "All AI runs on YOUR device. No third-party servers. No accounts. Optionally sync via your personal iCloud. Your mind belongs only to you.",
            background: Color(red: 20/255, green: 40/255, blue: 60/255),
            textColor: .white
        )
    ]

    var body: some View {
        ZStack {
            ConcentricPageTransitionView(
                pages: pages.map { page in
                    (OnboardingPageView(page: page), page.background)
                },
                currentIndex: $currentPage,
                duration: reduceMotion ? 0 : 0.8
            )

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            currentPage = pages.count - 1
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(pages[currentPage].textColor.opacity(0.65))
                        .padding(.horizontal, isIPad ? 44 : 24)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    }
                }
                .frame(height: 64)

                Spacer()

                HStack(spacing: 10) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? pages[currentPage].textColor : pages[currentPage].textColor.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .scaleEffect(index == currentPage ? 1.2 : 1)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 18)

                Button(action: {
                    if currentPage < pages.count - 1 {
                        currentPage += 1
                    } else {
                        completeOnboarding()
                    }
                }) {
                    HStack {
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Continue")
                            .font(.headline)
                        if currentPage == pages.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(pages[currentPage].background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(pages[currentPage].textColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                }
                .frame(maxWidth: isIPad ? 500 : .infinity)
                .padding(.horizontal, isIPad ? 60 : 28)
                .padding(.bottom, isIPad ? 56 : 44)
            }
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.3)) {
            hasCompletedOnboarding = true
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let background: Color
    let textColor: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(alignment: .center, spacing: isIPad ? 42 : 34) {
            Spacer()

            Text(page.title)
                .font(.system(size: isIPad ? 48 : 39, weight: .bold, design: .rounded))
                .foregroundColor(page.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: isIPad ? 620 : 340)
                .padding(.horizontal, 24)

            ZStack {
                Circle()
                    .fill(page.textColor.opacity(0.18))
                    .frame(width: isIPad ? 210 : 164, height: isIPad ? 210 : 164)

                Circle()
                    .stroke(page.textColor.opacity(0.28), lineWidth: 2)
                    .frame(width: isIPad ? 244 : 196, height: isIPad ? 244 : 196)

                Image(systemName: page.icon)
                    .font(.system(size: isIPad ? 84 : 66, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [page.textColor, page.iconColor.opacity(0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .center, spacing: 8) {
                Text(page.subtitle)
                    .font(.system(size: isIPad ? 28 : 24, weight: .bold, design: .rounded))
                    .foregroundColor(page.textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(page.description)
                    .font(.system(size: isIPad ? 20 : 17, weight: .bold, design: .rounded))
                    .foregroundColor(page.textColor.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: isIPad ? 560 : 330)
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Privacy Badge Component

struct PrivacyBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.green)

            if !compact {
                Text("100% Private")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 6)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Offline Indicator

struct OfflineIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("Offline")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
