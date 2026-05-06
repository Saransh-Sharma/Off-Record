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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    @State private var showMilestone: Int? = nil

    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if entries.isEmpty {
                    emptyStateCard
                } else {
                    // Shareable Weekly Insights
                    WeeklyInsightsSection(entries: Array(entries))

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
        .onAppear {
            if let milestone = goalManager.checkMilestone(currentStreak: currentStreak) {
                HapticManager.shared.streakMilestone()
                withAnimation(.spring(response: 0.5)) {
                    showMilestone = milestone
                }
            }
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
                    .foregroundColor(OffRecordColor.brandLavenderDark)
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
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundColor(OffRecordColor.textPeach)
                Text("Writing Streak")
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 4) {
                Text("\(currentStreak)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(OffRecordColor.textPeach)
                Text(currentStreak == 1 ? "day" : "days")
                    .font(.title3)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .padding(.bottom, 8)
                Spacer()
            }

            // Streak info
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Longest")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                    Text("\(longestStreak) days")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textPrimary)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading) {
                    Text("This Month")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                    Text("\(entriesThisMonth) entries")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textPrimary)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                    Text("\(entries.count) entries")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textPrimary)
                }

                Spacer()
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfacePeach)
    }

    // MARK: - Week Activity Card

    private var weekActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)

            HStack(spacing: 8) {
                ForEach(last7Days, id: \.self) { date in
                    let hasEntry = hasEntryOn(date)
                    VStack(spacing: 6) {
                        Circle()
                            .fill(hasEntry ? OffRecordColor.brandAqua : OffRecordColor.textTertiary.opacity(0.2))
                            .frame(width: isIPad ? 44 : 32, height: isIPad ? 44 : 32)
                            .overlay {
                                if hasEntry {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.white)
                                }
                            }
                        Text(dayAbbreviation(date))
                            .font(.caption2)
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

            if moodData.isEmpty {
                Text("Record entries with moods to see trends")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Mood distribution
                HStack(spacing: 12) {
                    ForEach(topMoods, id: \.mood) { item in
                        VStack(spacing: 6) {
                            Image(systemName: item.mood.icon)
                                .font(.title2)
                                .foregroundColor(item.mood.color)
                            Text("\(item.count)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(OffRecordColor.textPrimary)
                            Text(item.mood.displayName)
                                .font(.caption2)
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
            ForEach(moodChartData, id: \.date) { item in
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
                        Text(v == 1 ? "😔" : v == 3 ? "😐" : "😊")
                            .font(.caption)
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
                StatItem(title: "Total Words", value: "\(totalWords)", icon: "text.word.spacing", color: OffRecordColor.textSky)
                StatItem(title: "Avg Words/Entry", value: "\(avgWordsPerEntry)", icon: "chart.bar.fill", color: OffRecordColor.textMint)
                StatItem(title: "Starred", value: "\(starredCount)", icon: "star.fill", color: OffRecordColor.textYellow)
                StatItem(title: "With Audio", value: "\(audioCount)", icon: "waveform", color: OffRecordColor.textAqua)
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
    }

    // MARK: - AI Insights Card

    private var aiInsightsCard: some View {
        let insights = InsightsEngine.generateInsights(from: Array(entries))

        return Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(OffRecordColor.brandLavenderDark)
                        Text("AI Insights")
                            .font(.headline)
                            .foregroundColor(OffRecordColor.textHeading)
                    }

                    ForEach(insights.prefix(3)) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.icon)
                                .font(.title3)
                                .foregroundColor(colorFromName(insight.color))
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
        let summary = InsightsEngine.generateWeeklySummary(from: Array(entries))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(OffRecordColor.textSky)
                Text("Weekly reflection")
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
            }

            Text(summary)
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
    }

    // MARK: - Goal Progress Card

    private var goalProgressCard: some View {
        let progress = goalManager.progressThisWeek(from: Array(entries))
        let count = goalManager.entriesThisWeek(from: Array(entries))
        let remaining = goalManager.daysRemainingInWeek()

        return VStack(spacing: 16) {
            HStack {
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundColor(OffRecordColor.textAqua)
                Text("Weekly Goal")
                    .font(.headline)
                    .foregroundColor(OffRecordColor.textHeading)
                Spacer()
                Text("\(count)/\(goalManager.weeklyTarget)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(OffRecordColor.textAqua)
            }

            ZStack {
                Circle()
                    .stroke(OffRecordColor.borderSoft, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(OffRecordColor.brandAqua, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: progress)

                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.title2.bold())
                        .foregroundColor(OffRecordColor.textAqua)
                    Text("\(remaining) days left")
                        .font(.caption2)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            .frame(width: 100, height: 100)

            if progress >= 1.0 {
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
                .foregroundColor(.offRecordReadableTintedForeground)
                .offRecordGlassControl(tint: OffRecordColor.brandPeach, in: Capsule(), fallbackFill: OffRecordColor.surfacePeach)
            }
            .padding(32)
            .offRecordGlassBar(cornerRadius: 24, fallbackFill: Color(.systemBackground))
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

    // MARK: - Computed Properties

    private var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Check if there's an entry today
        if !hasEntryOn(checkDate) {
            // Check yesterday - streak might still be active
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            if !hasEntryOn(checkDate) {
                return 0
            }
        }

        // Count consecutive days
        while hasEntryOn(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        return streak
    }

    private var longestStreak: Int {
        let calendar = Calendar.current
        let sortedDates = entries.compactMap { $0.date }.map { calendar.startOfDay(for: $0) }
        let uniqueDates = Set(sortedDates).sorted(by: >)

        guard !uniqueDates.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for i in 1..<uniqueDates.count {
            let diff = calendar.dateComponents([.day], from: uniqueDates[i], to: uniqueDates[i-1]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        return longest
    }

    private var entriesThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return entries.filter { entry in
            guard let date = entry.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }.count
    }

    private var last7Days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.reversed()
    }

    private func hasEntryOn(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return entries.contains { entry in
            guard let entryDate = entry.date else { return false }
            return calendar.isDate(entryDate, inSameDayAs: date)
        }
    }

    private func dayAbbreviation(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(1))
    }

    private var moodData: [(mood: Mood, count: Int)] {
        var counts: [Mood: Int] = [:]
        for entry in entries {
            if let moodString = entry.value(forKey: "mood") as? String,
               let mood = Mood(rawValue: moodString),
               mood != .none {
                counts[mood, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var topMoods: [(mood: Mood, count: Int)] {
        Array(moodData.prefix(4))
    }

    private var moodChartData: [(date: Date, mood: Mood?)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<14).compactMap { offset -> (Date, Mood?)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let entry = entries.first { entry in
                guard let entryDate = entry.date else { return false }
                return calendar.isDate(entryDate, inSameDayAs: date)
            }
            let mood: Mood?
            if let moodString = entry?.value(forKey: "mood") as? String {
                mood = Mood(rawValue: moodString)
            } else {
                mood = nil
            }
            return (date, mood)
        }.reversed()
    }

    private var totalWords: Int {
        entries.reduce(0) { total, entry in
            let text = entry.text ?? ""
            return total + text.split { $0.isWhitespace || $0.isNewline }.count
        }
    }

    private var avgWordsPerEntry: Int {
        guard entries.count > 0 else { return 0 }
        return totalWords / entries.count
    }

    private var starredCount: Int {
        entries.filter { $0.isStarred }.count
    }

    private var audioCount: Int {
        entries.filter { entry in
            let fileName = entry.value(forKey: "audioFileName") as? String
            return fileName != nil && !fileName!.isEmpty
        }.count
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
