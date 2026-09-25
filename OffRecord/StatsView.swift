//
//  StatsView.swift
//  OffRecord
//
//  Insights: writing rhythm, mood charts, explainable AI insights, and the
//  single Weekly Reflection surface for this tab.
//

import SwiftUI
import CoreData

struct StatsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var weeklyReflection = WeeklyReflectionController.shared
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared
    private let proactiveReflection = ProactiveReflectionController.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        predicate: DiaryEntry.startedEntryPredicate,
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    @State private var showMilestone: Int? = nil
    @State private var showDeepDive: Bool = false
    @State private var stats: JournalStatsSnapshot = .empty
    @State private var charts: InsightChartsSnapshot = .empty
    @State private var startedEntriesForCards: [DiaryEntry] = []
    @State private var selectedWeeklyReflection: WeeklyReflectionReport?
    @State private var evidenceContext: InsightEvidenceContext?
    @State private var shareInsights: [ShareableInsight] = []
    @ScaledMetric(relativeTo: .title2) private var goalRingSize: CGFloat = 104

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var startedEntries: [DiaryEntry] { entries.startedEntries }
    private var weeklyReflectionRouteEntries: [DiaryEntry] {
        startedEntriesForCards.isEmpty ? startedEntries : startedEntriesForCards
    }
    private var entriesSignature: String {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.objectID.uriRepresentation().absoluteString)
            hasher.combine(entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0)
        }
        return String(hasher.finalize())
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = OffRecordAdaptiveMetrics(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            ScrollView {
                statsContent(metrics: metrics)
                    .padding(.horizontal, metrics.pageHorizontalPadding)
                    .padding(.vertical, OffRecordSpacing.lg)
                    .frame(maxWidth: metrics.pageMaxWidth ?? .infinity)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(OffRecordAppBackground())
        .navigationTitle("Insights")
        .overlay {
            if let milestone = showMilestone {
                MilestoneCelebrationView(days: milestone) {
                    withOffRecordAnimation(OffRecordMotion.fade) {
                        showMilestone = nil
                    }
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .sheet(item: $evidenceContext) { context in
            InsightEvidenceSheet(context: context)
        }
        .task(id: "\(entriesSignature)-\(goalManager.weeklyTarget)-\(goalManager.isEnabled)") {
            await refreshStats()
        }
        .navigationDestination(item: $selectedWeeklyReflection) { report in
            WeeklyReflectionReportView(report: report, entries: weeklyReflectionRouteEntries)
        }
        .onAppear {
            openPendingWeeklyReflectionRouteIfNeeded()
        }
        .onChange(of: navigationRouter.shouldOpenCurrentWeeklyReflection) { _, shouldOpen in
            guard shouldOpen else { return }
            openPendingWeeklyReflectionRouteIfNeeded()
        }
        .onChange(of: navigationRouter.routedWeeklyReflectionID) { _, id in
            guard let id else { return }
            selectedWeeklyReflection = weeklyReflection.report(id: id)
            navigationRouter.routedWeeklyReflectionID = nil
        }
    }

    private func openPendingWeeklyReflectionRouteIfNeeded() {
        guard navigationRouter.shouldOpenCurrentWeeklyReflection else { return }
        selectedWeeklyReflection = weeklyReflection.openCurrentReport(entries: weeklyReflectionRouteEntries)
        navigationRouter.shouldOpenCurrentWeeklyReflection = false
    }

    @ViewBuilder
    private func statsContent(metrics: OffRecordAdaptiveMetrics) -> some View {
        VStack(spacing: OffRecordSpacing.xl) {
            if stats.isEmpty && startedEntriesForCards.isEmpty {
                emptyStateCard
            } else {
                if metrics.mode >= .expanded {
                    LazyVGrid(
                        columns: metrics.insightsColumns(dynamicTypeSize: dynamicTypeSize),
                        spacing: OffRecordSpacing.lg
                    ) {
                        primaryCards
                    }
                } else {
                    primaryCards
                }

                deepDiveSection
            }
        }
    }

    @ViewBuilder
    private var primaryCards: some View {
        streakCard
        if goalManager.isEnabled {
            goalProgressCard
        }
        WeekActivityChartCard(days: charts.week)
        MoodTrendChartCard(points: charts.moodTrend)
        aiInsightsCard
        WeeklyReflectionHistorySection(entries: weeklyReflectionRouteEntries)
        WeeklyInsightsSection(entries: startedEntriesForCards, insights: shareInsights)
    }

    private var deepDiveSection: some View {
        DisclosureGroup(isExpanded: $showDeepDive) {
            VStack(spacing: OffRecordSpacing.xl) {
                MoodTimeHeatmapCard(snapshot: charts)
                statsSummaryCard
            }
            .padding(.top, OffRecordSpacing.md)
        } label: {
            Label("Deep Dive", systemImage: "chart.bar.doc.horizontal")
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textHeading)
                .frame(minHeight: OffRecordLayout.minimumTapTarget)
        }
        .tint(OffRecordColor.textSecondary)
        .accessibilityIdentifier("insights.deepDive")
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        EmptyStateView.noInsights
            .frame(maxWidth: .infinity)
            .offRecordContentCard()
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        StreakCardView(
            currentStreak: stats.currentStreak,
            longestStreak: stats.longestStreak,
            entriesThisMonth: stats.entriesThisMonth,
            totalEntries: stats.entryCount,
            isIPad: isIPad
        )
    }

    // MARK: - Stats Summary Card

    private var statsSummaryCard: some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : (isIPad ? 4 : 2)
        return VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: "Writing Stats", systemImage: "text.word.spacing", tint: OffRecordColor.textSky)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OffRecordSpacing.md), count: columnCount), spacing: OffRecordSpacing.md) {
                StatItem(title: "Total Words", value: "\(stats.totalWords)", icon: "text.word.spacing", color: OffRecordColor.textSky)
                StatItem(title: "Avg Words/Entry", value: "\(stats.avgWordsPerEntry)", icon: "chart.bar.fill", color: OffRecordColor.textMint)
                StatItem(title: "Starred", value: "\(stats.starredCount)", icon: "star.fill", color: OffRecordColor.textYellow)
                StatItem(title: "With Audio", value: "\(stats.audioCount)", icon: "waveform", color: OffRecordColor.textAqua)
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
    }

    // MARK: - AI Insights Card

    @ViewBuilder
    private var aiInsightsCard: some View {
        if !stats.insights.isEmpty {
            VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
                InsightCardHeader(title: "AI Insights", systemImage: "sparkles", tint: OffRecordColor.textLavender)
                Text("Observations from your entries, worked out on your device.")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(stats.insights.prefix(4).enumerated()), id: \.element.id) { index, insight in
                    if index > 0 {
                        Divider().overlay(OffRecordColor.hairline)
                    }
                    insightRow(insight)
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("insights.aiInsights")
        }
    }

    private func insightRow(_ insight: JournalInsightSummary) -> some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(systemImage: insight.icon, tint: insightTint(insight.colorName), size: 36, iconSize: 15)

            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text(insight.title)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                Text(insight.description)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.supportingEntryIDs.isEmpty {
                    InsightWhyButton {
                        evidenceContext = InsightEvidenceContext(
                            id: insight.id,
                            title: insight.title,
                            summary: insight.description,
                            rationale: insight.rationale,
                            entries: startedEntriesForCards.resolvingInsightEvidence(insight.supportingEntryIDs)
                        )
                    }
                    .accessibilityIdentifier("insights.why.\(insight.id)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, OffRecordSpacing.xs)
    }

    // MARK: - Goal Progress Card

    private var goalProgressCard: some View {
        let percent = Int((stats.goal.progress * 100).rounded())
        let reached = stats.goal.progress >= 1.0
        return VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            HStack {
                InsightCardHeader(title: "Weekly Goal", systemImage: "target", tint: OffRecordColor.textAqua)
                Text("\(stats.goal.count)/\(stats.goal.weeklyTarget)")
                    .font(OffRecordTypography.numberSmall)
                    .foregroundStyle(OffRecordColor.textAqua)
                    .accessibilityHidden(true)
            }

            HStack(spacing: OffRecordSpacing.xl) {
                ZStack {
                    Circle()
                        .stroke(OffRecordColor.borderSoft, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: stats.goal.progress)
                        .stroke(OffRecordColor.brandAqua, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .offRecordAnimation(OffRecordMotion.gentle, value: stats.goal.progress)

                    Text("\(percent)%")
                        .font(OffRecordTypography.numberSmall)
                        .foregroundStyle(OffRecordColor.textAqua)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(OffRecordSpacing.md)
                }
                .frame(width: goalRingSize, height: goalRingSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weekly goal progress")
                .accessibilityValue("\(percent) percent, \(stats.goal.count) of \(stats.goal.weeklyTarget) journaling days, \(stats.goal.daysRemaining) \(stats.goal.daysRemaining == 1 ? "day" : "days") to go")
                .accessibilityIdentifier("insights.goal.ring")

                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text(reached ? "Goal reached this week" : "\(stats.goal.count) of \(stats.goal.weeklyTarget) journaling days")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(reached ? OffRecordColor.textSage : OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reached ? "Anything more is a bonus." : "\(stats.goal.daysRemaining) \(stats.goal.daysRemaining == 1 ? "day" : "days") to go this week.")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    private func insightTint(_ name: String) -> Color {
        switch name {
        case "orange": return OffRecordColor.textPeach
        case "green": return OffRecordColor.textMint
        case "blue": return OffRecordColor.textSky
        case "yellow": return OffRecordColor.textYellow
        case "pink": return OffRecordColor.textBlush
        case "purple", "indigo": return OffRecordColor.textLavender
        default: return OffRecordColor.textSecondary
        }
    }

    @MainActor
    private func refreshStats() async {
        let token = PerformanceSignposts.begin("StatsViewRefresh")
        let currentEntries = startedEntries
        let snapshots = currentEntries.journalSnapshots
        let now = Date()
        let nextStats = await JournalAnalyticsWorker.shared.makeStats(
            from: snapshots,
            now: now,
            weeklyTarget: goalManager.weeklyTarget,
            goalEnabled: goalManager.isEnabled
        )

        guard !Task.isCancelled else {
            PerformanceSignposts.end(token)
            return
        }

        startedEntriesForCards = currentEntries
        stats = nextStats
        charts = InsightChartsSnapshot.make(from: snapshots, now: now)
        shareInsights = ShareableInsightGenerator.generateWeeklyInsights(from: currentEntries)
        proactiveReflection.refreshIfNeeded(entries: currentEntries)
        weeklyReflection.refreshIfNeeded(entries: currentEntries)
        if let milestone = goalManager.checkMilestone(currentStreak: nextStats.currentStreak) {
            // MilestoneCelebrationView plays the success haptic itself.
            withOffRecordAnimation(OffRecordMotion.bouncy) {
                showMilestone = milestone
            }
        }
        PerformanceSignposts.end(token)
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .font(OffRecordTypography.numberSmall)
                .foregroundStyle(OffRecordColor.textPrimary)
            Text(title)
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.md, fill: OffRecordColor.surfacePrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

#Preview {
    NavigationStack {
        StatsView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
