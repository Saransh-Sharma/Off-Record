//
//  ShareableInsightCardView.swift
//  OffRecord
//
//  Weekly insight cards, the carousel that shows them on Insights, and the
//  privacy-first share flow (names hidden unless the person opts in).
//

import SwiftUI

private extension ShareableInsight.Category {
    /// Readable foreground for small labels and icons.
    var textTint: Color {
        switch self {
        case .emotion: return OffRecordColor.textBlush
        case .pattern: return OffRecordColor.textLavender
        case .people: return OffRecordColor.textPeach
        case .language: return OffRecordColor.textAqua
        case .growth: return OffRecordColor.textMint
        case .time: return OffRecordColor.textSky
        }
    }

    /// Soft accent used for strokes and dots.
    var accentFill: Color {
        switch self {
        case .emotion: return OffRecordColor.brandBlush
        case .pattern: return OffRecordColor.brandLavenderDark
        case .people: return OffRecordColor.brandPeach
        case .language: return OffRecordColor.brandAqua
        case .growth: return OffRecordColor.brandMint
        case .time: return OffRecordColor.brandSky
        }
    }
}

// MARK: - Card View

struct ShareableInsightCardView: View {
    let insight: ShareableInsight
    let onShare: () -> Void
    var onWhy: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            Label("Weekly Insight", systemImage: insight.category.icon)
                .font(OffRecordTypography.badgeLabel)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(insight.category.textTint)

            Text(insight.headline)
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textHeading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(insight.subtext)
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OffRecordColor.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let dataPoint = insight.dataPoint {
                HStack(spacing: OffRecordSpacing.sm) {
                    Circle()
                        .fill(insight.category.accentFill)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(dataPoint)
                        .font(OffRecordTypography.metadata.monospaced())
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
            }

            Spacer(minLength: 0)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: OffRecordSpacing.md) {
                    whyButton
                    Spacer(minLength: 0)
                    shareButton
                }
                VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                    whyButton
                    shareButton
                }
            }
        }
        .padding(OffRecordSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [OffRecordColor.surfaceWarm, OffRecordColor.surfaceLavender],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                        .stroke(insight.category.accentFill.opacity(0.25), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var whyButton: some View {
        if let onWhy {
            InsightWhyButton(action: onWhy)
                .accessibilityIdentifier("insights.weekly.why")
        }
    }

    private var shareButton: some View {
        Button(action: onShare) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandPlum))
        .accessibilityHint("Previews a shareable image. Names stay hidden unless you include them.")
        .accessibilityIdentifier("insights.weekly.share")
    }
}

// MARK: - Card Renderer (for sharing as image)

struct InsightCardRenderer {
    /// Renders the insight card as a UIImage for sharing
    @MainActor
    static func renderCard(insight: ShareableInsight) -> UIImage? {
        let cardView = ShareableCardForExport(insight: insight)
            .frame(width: 380, height: 420)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 3.0 // High resolution
        return renderer.uiImage
    }
}

/// Standalone card view for image export (fixed canvas, no buttons, extra branding).
private struct ShareableCardForExport: View {
    let insight: ShareableInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Weekly Insight", systemImage: insight.category.icon)
                .font(OffRecordExportTypography.label)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(insight.category.textTint)

            Spacer()

            Text(insight.headline)
                .font(OffRecordExportTypography.headline)
                .foregroundStyle(OffRecordColor.textHeading)
                .lineSpacing(6)

            Text(insight.subtext)
                .font(OffRecordExportTypography.body)
                .foregroundStyle(OffRecordColor.textSecondary)
                .lineSpacing(3)

            if let dataPoint = insight.dataPoint {
                HStack(spacing: 6) {
                    Circle()
                        .fill(insight.category.accentFill)
                        .frame(width: 6, height: 6)
                    Text(dataPoint)
                        .font(OffRecordExportTypography.monospaced)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
            }

            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OffRecord AI Journal")
                        .font(OffRecordExportTypography.brand)
                        .foregroundStyle(OffRecordColor.textSecondary)
                    Text("Private, on-device voice diary")
                        .font(OffRecordExportTypography.micro)
                        .foregroundStyle(OffRecordColor.textTertiary)
                }
                Spacer()
                Text("OffRecord")
                    .font(OffRecordExportTypography.monospaced)
                    .foregroundStyle(OffRecordColor.textTertiary)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [OffRecordColor.surfaceWarm, OffRecordColor.surfaceLavender],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(insight.category.accentFill.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Share preview

/// Shows exactly what will be shared, with names hidden by default.
struct ShareInsightPreviewSheet: View {
    let insight: ShareableInsight
    @Environment(\.dismiss) private var dismiss
    @State private var includeNames = false
    @State private var renderedImage: UIImage?

    private var protectedNames: [String] { insight.namesToProtect }
    private var shareable: ShareableInsight { insight.sharingVersion(includeNames: includeNames) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffRecordSpacing.xl) {
                    preview

                    if !protectedNames.isEmpty {
                        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                            Toggle(isOn: $includeNames) {
                                Label("Include names", systemImage: "person.crop.circle")
                                    .font(OffRecordTypography.labelLarge)
                                    .foregroundStyle(OffRecordColor.textPrimary)
                            }
                            .tint(OffRecordColor.brandSageDark)
                            .accessibilityIdentifier("insights.share.includeNames")

                            Text(includeNames
                                 ? "Names will appear in the image. Only share if they'd be comfortable with it."
                                 : "Names are replaced with \u{201C}someone\u{201D} so the people in your journal stay private.")
                                .font(OffRecordTypography.metadata)
                                .foregroundStyle(OffRecordColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(OffRecordSpacing.lg)
                        .offRecordCard(cornerRadius: OffRecordRadius.md, shadow: false)
                    }

                    OffRecordPrivacyBadge(title: "Only this card is shared", subtitle: "Your entries never leave your device.")

                    if let renderedImage {
                        ShareLink(
                            item: Image(uiImage: renderedImage),
                            preview: SharePreview(shareable.headline, image: Image(uiImage: renderedImage))
                        ) {
                            Label("Share image", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .offRecordPillButton()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("insights.share.confirm")
                    }
                }
                .padding(OffRecordSpacing.screenX)
                .frame(maxWidth: OffRecordLayout.readableContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(OffRecordAppBackground().ignoresSafeArea())
            .navigationTitle("Share Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: includeNames) {
            renderedImage = InsightCardRenderer.renderCard(insight: shareable)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let renderedImage {
            Image(uiImage: renderedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)
                .offRecordShadow(.card)
                .accessibilityLabel("Preview: \(shareable.headline) \(shareable.subtext)")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

// MARK: - Insights Section (for StatsView integration)

struct WeeklyInsightsSection: View {
    let entries: [DiaryEntry]
    @State private var insights: [ShareableInsight] = []
    @State private var currentID: UUID?
    @State private var sharingInsight: ShareableInsight?
    @State private var evidenceContext: InsightEvidenceContext?

    private var entriesSignature: String {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.insightEvidenceKey)
            hasher.combine(entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0)
        }
        return String(hasher.finalize())
    }

    private var currentIndex: Int {
        insights.firstIndex { $0.id == currentID } ?? 0
    }

    var body: some View {
        Group {
            if !insights.isEmpty {
                insightsContent
            }
        }
        .task(id: entriesSignature) { generateInsights() }
        .sheet(item: $sharingInsight) { insight in
            ShareInsightPreviewSheet(insight: insight)
        }
        .sheet(item: $evidenceContext) { context in
            InsightEvidenceSheet(context: context)
        }
    }

    private var insightsContent: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: "Your Week, Decoded", systemImage: "sparkles", tint: OffRecordColor.textLavender)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                    ForEach(insights) { insight in
                        ShareableInsightCardView(
                            insight: insight,
                            onShare: { sharingInsight = insight },
                            onWhy: insight.supportingEntryIDs.isEmpty ? nil : { showEvidence(for: insight) }
                        )
                        .containerRelativeFrame(.horizontal)
                        .frame(maxHeight: .infinity)
                        .id(insight.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("insights.weekly.carousel")

            if insights.count > 1 {
                InsightPageDots(count: insights.count, selectedIndex: currentIndex) { index in
                    withOffRecordAnimation(OffRecordMotion.snappy) {
                        currentID = insights[index].id
                    }
                }
            }
        }
        .padding(.vertical, OffRecordSpacing.sm)
    }

    private func showEvidence(for insight: ShareableInsight) {
        evidenceContext = InsightEvidenceContext(
            id: insight.id.uuidString,
            title: insight.headline.replacingOccurrences(of: "\n", with: " "),
            summary: insight.subtext,
            rationale: insight.rationale,
            entries: entries.resolvingInsightEvidence(insight.supportingEntryIDs)
        )
    }

    private func generateInsights() {
        insights = ShareableInsightGenerator.generateWeeklyInsights(from: entries)
        currentID = insights.first?.id
    }
}

/// Page indicator for the insight carousel; adjustable with VoiceOver.
struct InsightPageDots: View {
    let count: Int
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: OffRecordSpacing.sm) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? OffRecordColor.brandLavenderDark : OffRecordColor.textTertiary.opacity(0.35))
                    .frame(width: index == selectedIndex ? 18 : 7, height: 7)
                    .frame(width: 26, height: OffRecordLayout.minimumTapTarget)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(index) }
            }
        }
        .offRecordAnimation(OffRecordMotion.snappy, value: selectedIndex)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Insight")
        .accessibilityValue("\(selectedIndex + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(count - 1, selectedIndex + 1))
            case .decrement: onSelect(max(0, selectedIndex - 1))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("insights.weekly.pageDots")
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            ShareableInsightCardView(
                insight: ShareableInsight(
                    headline: "You said \"should\" 14 times this week.\n\"Want\"? 2.",
                    subtext: "Lots of obligations on the page. Just something to notice.",
                    category: .language,
                    dataPoint: "should: 14 vs want: 2",
                    generatedAt: Date()
                ),
                onShare: {},
                onWhy: {}
            )

            ShareableInsightCardView(
                insight: ShareableInsight(
                    headline: "You mentioned Sarah 8 times this week.",
                    subtext: "Those entries tend to read a little lighter.",
                    category: .people,
                    dataPoint: "8x",
                    generatedAt: Date(),
                    personNames: ["Sarah"]
                ),
                onShare: {}
            )
        }
        .padding()
    }
    .background(OffRecordColor.backgroundPrimary)
}
