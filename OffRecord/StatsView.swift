//
//  StatsView.swift
//  OffRecord
//
//  Writing streaks and mood trends
//

import SwiftUI
import CoreData
import Charts

struct StatsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var proactiveReflection = ProactiveReflectionController.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        predicate: DiaryEntry.startedEntryPredicate,
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    @State private var showMilestone: Int? = nil
    @State private var stats: JournalStatsSnapshot = .empty
    @State private var startedEntriesForCards: [DiaryEntry] = []

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var startedEntries: [DiaryEntry] { entries.startedEntries }
    private var entriesSignature: String {
        entries.map { entry in
            let updated = entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0
            return "\(entry.objectID.uriRepresentation().absoluteString):\(updated)"
        }
        .joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if stats.isEmpty && startedEntriesForCards.isEmpty {
                    emptyStateCard
                } else {
                    // Shareable Weekly Insights
                    WeeklyInsightsSection(entries: startedEntriesForCards)

                    // Proactive weekly reflection
                    ProactiveWeeklyReflectionCard(entries: startedEntriesForCards)

                    // AI Insights
                    aiInsightsCard

                    // Streak Card
                    streakCard

                    // Goal Progress Card
                    if goalManager.isEnabled {
                        goalProgressCard
                    }

                    // This Week Activity
                    weekActivityCard

                    // Mood Trends
                    moodTrendsCard

                    // Stats Summary
                    statsSummaryCard

                    // Weekly Summary
                    weeklySummaryCard
                }
            }
            .padding()
            .frame(maxWidth: isIPad ? 700 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(OffRecordColor.appBackgroundGradient)
        .navigationTitle("Insights")
        .overlay {
            if let milestone = showMilestone {
                milestoneOverlay(days: milestone)
            }
        }
        .task(id: "\(entriesSignature)-\(goalManager.weeklyTarget)-\(goalManager.isEnabled)") {
            await refreshStats()
        }
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(OffRecordColor.surfaceLavender)
                    .frame(width: 80, height: 80)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 32))
                    .foregroundColor(OffRecordColor.textLavender)
            }

            Text("Insights will appear here")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)

            Text("Record a few entries and OffRecord AI Journal will show streaks, mood trends, and gentle summaries of your writing.")
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
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

    // MARK: - Week Activity Card

    private var weekActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)

            HStack(spacing: 8) {
                ForEach(stats.last7Days) { day in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(day.hasEntry ? OffRecordColor.surfaceMint : OffRecordColor.textTertiary.opacity(0.16))
                            .frame(width: isIPad ? 44 : 32, height: isIPad ? 44 : 32)
                            .overlay {
                                if day.hasEntry {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(OffRecordColor.textAqua)
                                }
                            }
                        Text(day.label)
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    // MARK: - Mood Trends Card

    private var moodTrendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood Trends")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)

            if stats.moodCounts.isEmpty {
                Text("Record entries with moods to see trends")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Mood distribution
                HStack(spacing: 12) {
                    ForEach(stats.moodCounts.prefix(4)) { item in
                        VStack(spacing: 6) {
                            MiniMoodIcon(
                                mood: item.mood,
                                size: 24,
                                opacity: 0.88
                            )
                            Text("\(item.count)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(OffRecordColor.textPrimary)
                            Text(item.mood.displayName)
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Mood chart (last 14 days)
                if #available(iOS 16.0, *) {
                    moodChart
                        .frame(height: 120)
                        .padding(.top, 8)
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    @available(iOS 16.0, *)
    private var moodChart: some View {
        Chart {
            ForEach(stats.moodChartData) { item in
                if let mood = item.mood {
                    PointMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Mood", mood.moodValue)
                    )
                    .foregroundStyle(mood.color)
                    .symbolSize(100)
                }
            }
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 3, 5]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        MiniMoodIcon(
                            mood: chartAxisMood(for: v),
                            size: 14,
                            opacity: 0.78,
                            accessibilityLabel: "\(chartAxisMood(for: v).displayName) mood"
                        )
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { value in
                AxisValueLabel(format: .dateTime.day())
            }
        }
    }

    // MARK: - Stats Summary Card

    private var statsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Writing Stats")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: isIPad ? 4 : 2), spacing: 16) {
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

    private var aiInsightsCard: some View {
        Group {
            if !stats.insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(OffRecordColor.textLavender)
                        Text("AI Insights")
                            .font(.headline)
                            .foregroundColor(OffRecordColor.textHeading)
                    }

                    ForEach(stats.insights.prefix(3)) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.icon)
                                .font(.title3)
                                .foregroundColor(colorFromName(insight.colorName))
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(OffRecordColor.textPrimary)
                                Text(insight.description)
                                    .font(.caption)
                                    .foregroundColor(OffRecordColor.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
            }
        }
    }

    // MARK: - Weekly Summary Card

    private var weeklySummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(OffRecordColor.textSky)
                Text("Weekly reflection")
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
            }

            Text(stats.weeklySummary)
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
    }

    // MARK: - Goal Progress Card

    private var goalProgressCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundColor(OffRecordColor.textAqua)
                Text("Weekly Goal")
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
                Spacer()
                Text("\(stats.goal.count)/\(stats.goal.weeklyTarget)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(OffRecordColor.textAqua)
            }

            ZStack {
                Circle()
                    .stroke(OffRecordColor.borderSoft, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: stats.goal.progress)
                    .stroke(OffRecordColor.brandAqua, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: stats.goal.progress)

                VStack(spacing: 2) {
                    Text("\(Int(stats.goal.progress * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(OffRecordColor.textAqua)
                    Text("\(stats.goal.daysRemaining) days left")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            .frame(width: 100, height: 100)

            if stats.goal.progress >= 1.0 {
                Text("Goal reached! Great work this week.")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSage)
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    // MARK: - Milestone Overlay

    private func milestoneOverlay(days: Int) -> some View {
        ZStack {
            OffRecordColor.textBrand.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showMilestone = nil
                    }
                }

            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundColor(OffRecordColor.textYellow)

                Text("Milestone!")
                    .font(.largeTitle.bold())
                    .foregroundColor(OffRecordColor.textHeading)

                Text("\(days)-Day Streak")
                    .font(.title2)
                    .foregroundColor(OffRecordColor.textPeach)

                Text("You've journaled for \(days) consecutive days. Your dedication to self-reflection is paying off.")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Keep Going") {
                    withAnimation {
                        showMilestone = nil
                    }
                }
                .font(.headline)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .foregroundColor(OffRecordReadableTintStyle.journal.foreground)
                .offRecordGlassControl(
                    tint: OffRecordReadableTintStyle.journal.tint,
                    in: Capsule(),
                    fallbackFill: OffRecordReadableTintStyle.journal.fill,
                    border: OffRecordReadableTintStyle.journal.border
                )
            }
            .padding(32)
            .offRecordGlassBar(cornerRadius: 24, fallbackFill: OffRecordColor.surfaceWarm)
            .shadow(radius: 20)
            .padding(40)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "orange": return OffRecordColor.brandPeach
        case "green": return OffRecordColor.brandMint
        case "blue": return OffRecordColor.brandSky
        case "yellow": return OffRecordColor.brandYellow
        case "pink": return OffRecordColor.brandBlush
        case "purple": return OffRecordColor.brandLavenderDark
        case "indigo": return OffRecordColor.brandLavender
        default: return OffRecordColor.textSecondary
        }
    }

    private func chartAxisMood(for value: Int) -> Mood {
        switch value {
        case 1:
            return .sad
        case 3:
            return .none
        case 5:
            return .happy
        default:
            return .none
        }
    }

    @MainActor
    private func refreshStats() async {
        let token = PerformanceSignposts.begin("StatsViewRefresh")
        let currentEntries = startedEntries
        let snapshots = currentEntries.journalSnapshots
        let nextStats = await JournalAnalyticsWorker.shared.makeStats(
            from: snapshots,
            now: Date(),
            weeklyTarget: goalManager.weeklyTarget,
            goalEnabled: goalManager.isEnabled
        )

        guard !Task.isCancelled else {
            PerformanceSignposts.end(token)
            return
        }

        startedEntriesForCards = currentEntries
        stats = nextStats
        proactiveReflection.refreshIfNeeded(entries: currentEntries)
        if let milestone = goalManager.checkMilestone(currentStreak: nextStats.currentStreak) {
            HapticManager.shared.streakMilestone()
            withAnimation(.spring(response: 0.5)) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundColor(OffRecordColor.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.md, fill: OffRecordColor.surfacePrimary)
    }
}

// MARK: - Mood Extension for Chart

extension Mood {
    var moodValue: Int {
        switch self {
        case .happy, .excited, .grateful: return 5
        case .calm: return 4
        case .tired: return 3
        case .anxious: return 2
        case .sad, .angry: return 1
        case .none: return 3
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
