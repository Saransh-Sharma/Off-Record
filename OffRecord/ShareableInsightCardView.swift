//
//  ShareableInsightCardView.swift
//  OffRecord
//
//  Renders a clean, shareable insight card designed for social media.
//  Dark background, bold typography, subtle branding.
//  Optimized for Instagram Stories, TikTok, and Twitter.
//

import SwiftUI

// MARK: - Shareable Card View

struct ShareableInsightCardView: View {
    let insight: ShareableInsight
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            cardContent
                .padding(.bottom, 12)

            // Share button
            Button(action: onShare) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Share")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(OffRecordColor.textInverse)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(OffRecordColor.brandPlum.opacity(0.88)))
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Category badge
            HStack(spacing: 6) {
                Image(systemName: insight.category.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("Weekly Insight")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            .foregroundColor(categoryColor.opacity(0.9))

            // Headline
            Text(insight.headline)
                .font(.system(size: 22, weight: .bold, design: .default))
                .foregroundColor(OffRecordColor.textHeading)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Subtext
            Text(insight.subtext)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(OffRecordColor.textSecondary)
                .lineSpacing(2)

            // Data point badge (if available)
            if let dataPoint = insight.dataPoint {
                HStack(spacing: 6) {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 6, height: 6)
                    Text(dataPoint)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }

            Spacer().frame(height: 4)

            // Branding
            HStack {
                Spacer()
                Text("OffRecord AI Journal")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(OffRecordColor.textTertiary)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OffRecordColor.surfaceWarm,
                            OffRecordColor.surfaceLavender
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(categoryColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var categoryColor: Color {
        switch insight.category {
        case .emotion: return OffRecordColor.brandBlush
        case .pattern: return OffRecordColor.brandLavenderDark
        case .people: return OffRecordColor.brandPeach
        case .language: return OffRecordColor.brandAqua
        case .growth: return OffRecordColor.brandMint
        case .time: return OffRecordColor.brandSky
        }
    }
}

// MARK: - Card Renderer (for sharing as image)

struct InsightCardRenderer {
    /// Renders the insight card as a UIImage for sharing
    @MainActor
    static func renderCard(insight: ShareableInsight) -> UIImage? {
        let cardView = ShareableCardForExport(insight: insight)
            .frame(width: 380, height: 420)

        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 3.0 // High resolution
        return renderer.uiImage
    }
}

/// Standalone card view for image export (no share button, includes extra branding)
private struct ShareableCardForExport: View {
    let insight: ShareableInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Category badge
            HStack(spacing: 6) {
                Image(systemName: insight.category.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text("Weekly Insight")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            .foregroundColor(categoryColor.opacity(0.9))

            Spacer()

            // Headline
            Text(insight.headline)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(OffRecordColor.textHeading)
                .lineSpacing(6)

            // Subtext
            Text(insight.subtext)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(OffRecordColor.textSecondary)
                .lineSpacing(3)

            // Data point
            if let dataPoint = insight.dataPoint {
                HStack(spacing: 6) {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 6, height: 6)
                    Text(dataPoint)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }

            Spacer()

            // Branding footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OffRecord AI Journal")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(OffRecordColor.textSecondary)
                    Text("AI Voice Diary")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(OffRecordColor.textTertiary)
                }
                Spacer()
                Text("OffRecord")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(OffRecordColor.textTertiary)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OffRecordColor.surfaceWarm,
                            OffRecordColor.surfaceLavender
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(categoryColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var categoryColor: Color {
        switch insight.category {
        case .emotion: return OffRecordColor.brandBlush
        case .pattern: return OffRecordColor.brandLavenderDark
        case .people: return OffRecordColor.brandPeach
        case .language: return OffRecordColor.brandAqua
        case .growth: return OffRecordColor.brandMint
        case .time: return OffRecordColor.brandSky
        }
    }
}

// MARK: - Insights Section (for StatsView integration)

struct WeeklyInsightsSection: View {
    let entries: [DiaryEntry]
    @State private var insights: [ShareableInsight] = []
    @State private var currentIndex = 0
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    var body: some View {
        Group {
            if !insights.isEmpty {
                insightsContent
            }
        }
        .onAppear { generateInsights() }
    }

    private var insightsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(OffRecordColor.brandLavenderDark)
                Text("Your Week, Decoded")
                    .font(.headline)
                Spacer()
                if insights.count > 1 {
                    Text("\(currentIndex + 1)/\(insights.count)")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }

            // Card carousel
            TabView(selection: $currentIndex) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    ShareableInsightCardView(insight: insight) {
                        shareInsight(insight)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 280)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [image])
            }
        }
    }

    private func generateInsights() {
        insights = ShareableInsightGenerator.generateWeeklyInsights(from: entries)
    }

    private func shareInsight(_ insight: ShareableInsight) {
        Task { @MainActor in
            if let image = InsightCardRenderer.renderCard(insight: insight) {
                shareImage = image
                showShareSheet = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            ShareableInsightCardView(
                insight: ShareableInsight(
                    headline: "You said \"should\" 14 times this week.\n\"Want\"? Only 2.",
                    subtext: "You're living by obligation, not desire.",
                    category: .language,
                    dataPoint: "should: 14 vs want: 2",
                    generatedAt: Date()
                )
            ) {}

            ShareableInsightCardView(
                insight: ShareableInsight(
                    headline: "You mentioned Sarah 8 times this week.",
                    subtext: "Your mood drops when you do.",
                    category: .people,
                    dataPoint: "8x",
                    generatedAt: Date()
                )
            ) {}

            ShareableInsightCardView(
                insight: ShareableInsight(
                    headline: "Most anxious on Sundays.\nMost calm on Wednesdays.",
                    subtext: "Your week has a pattern. Do you see it?",
                    category: .time,
                    dataPoint: nil,
                    generatedAt: Date()
                )
            ) {}
        }
        .padding()
    }
    .background(OffRecordColor.backgroundPrimary)
}
