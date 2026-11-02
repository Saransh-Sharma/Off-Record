//
//  PeriodReviewViews.swift
//  OffRecord
//
//  Month in Review and Year in Review: the Insights cards, the review screen,
//  and the Year in Pixels grid.
//

import Charts
import CoreData
import SwiftUI

// MARK: - Insights cards

/// One card: last month's review on top, earlier months as rows.
struct MonthInReviewSection: View {
    let onOpen: (PeriodReviewRoute) -> Void
    @ObservedObject private var controller = PeriodReviewController.shared

    private var lastMonthKey: String {
        let period = ReflectionPeriodCalendar.lastCompletedPeriod(.month, before: Date())
        return ReflectionPeriodCalendar.key(for: period, kind: .month)
    }

    private var latest: PeriodReview? { controller.review(kind: .month, key: lastMonthKey) }
    private var earlier: [PeriodReview] {
        Array(controller.monthReviews.filter { $0.periodKey != lastMonthKey }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: String(localized: "Month in Review"), systemImage: "calendar", tint: OffRecordColor.textPeach)

            if let latest {
                Button { onOpen(route(for: latest)) } label: { latestCard(latest) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("monthInReview.latest")
            } else {
                InsightChartEmptyState(
                    systemImage: "calendar.badge.clock",
                    message: String(localized: "After \(ReflectionPeriodKind.month.thresholds.minimumEntryCount) entries in a month, I’ll put a review here.")
                )
                .accessibilityIdentifier("monthInReview.empty")
            }

            if !earlier.isEmpty {
                Text("Earlier Months")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .padding(.top, OffRecordSpacing.xs)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(earlier.enumerated()), id: \.element.id) { index, review in
                    if index > 0 { Divider().overlay(OffRecordColor.hairline) }
                    Button { onOpen(route(for: review)) } label: {
                        PeriodReviewRow(title: review.periodTitle, subtitle: review.rowSubtitle, systemImage: "doc.text")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("monthInReview.row")
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monthInReview.section")
    }

    private func route(for review: PeriodReview) -> PeriodReviewRoute {
        let components = Calendar.current.dateComponents([.year, .month], from: review.report.periodStart)
        return PeriodReviewRoute(kind: .month, year: components.year ?? 0, month: components.month)
    }

    private func latestCard(_ review: PeriodReview) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.periodTitle)
                    .font(OffRecordTypography.badgeLabel)
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(OffRecordColor.textPeach)
                Spacer(minLength: OffRecordSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(review.report.heroSentence)
                .font(OffRecordTypography.bodySmall)
                .italic()
                .foregroundStyle(OffRecordColor.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Label(review.rowSubtitle, systemImage: "book.pages")
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textPeach)
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous))
    }
}

/// Rows for each year whose review can open now. Hidden when there are none.
struct YearInReviewSection: View {
    let years: [Int]
    let onOpen: (PeriodReviewRoute) -> Void

    var body: some View {
        if !years.isEmpty {
            VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
                InsightCardHeader(title: String(localized: "Year in Review"), systemImage: "sparkles.rectangle.stack", tint: OffRecordColor.textLavender)
                ForEach(Array(years.enumerated()), id: \.element) { index, year in
                    if index > 0 { Divider().overlay(OffRecordColor.hairline) }
                    Button {
                        onOpen(PeriodReviewRoute(kind: .year, year: year, month: nil))
                    } label: {
                        PeriodReviewRow(title: String(year), subtitle: nil, systemImage: "square.grid.3x3.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yearInReview.row.\(year)")
                }
            }
            .padding()
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("yearInReview.section")
        }
    }
}

private struct PeriodReviewRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: OffRecordSpacing.md) {
            Image(systemName: systemImage)
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textPeach)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text(title)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, OffRecordSpacing.sm)
        .frame(minHeight: OffRecordLayout.minimumTapTarget)
        .contentShape(Rectangle())
    }
}

extension PeriodReview {
    /// "September 2026" for a month, "2026" for a year.
    var periodTitle: String {
        switch kind {
        case .year:
            return String(Calendar.current.component(.year, from: report.periodStart))
        case .month, .week:
            return report.periodStart.formatted(.dateTime.month(.wide).year())
        }
    }

    var rowSubtitle: String {
        switch report.status {
        case .insufficientData: return String(localized: "Not enough entries yet")
        case .failed: return String(localized: "Couldn’t be made", comment: "Weekly reflection history row: the reflection failed to generate")
        default: return String(AttributedString(localized: "^[\(stats.entryCount) entry](inflect: true)").characters)
        }
    }
}

// MARK: - Review screen

/// Opens a review from a route: finds it, or builds it if it's missing or out of date.
struct PeriodReviewScreen: View {
    let route: PeriodReviewRoute
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var controller = PeriodReviewController.shared
    @State private var review: PeriodReview?
    @State private var entries: [DiaryEntry] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if let review {
                PeriodReviewDetailView(review: review, entries: entries)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("periodReview.loading")
            } else {
                ContentUnavailableView {
                    Label(route.kind == .year ? String(localized: "No Year in Review") : String(localized: "No Month in Review"), systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(unavailableMessage)
                }
                .accessibilityIdentifier("periodReview.unavailable")
            }
        }
        .background(OffRecordAppBackground().ignoresSafeArea())
        .navigationTitle(route.kind == .year ? String(localized: "Year in Review") : String(localized: "Month in Review"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: route) { await load() }
    }

    private var unavailableMessage: String {
        if route.kind == .year, route.year == Calendar.current.component(.year, from: Date()) {
            return String(localized: "This year’s review opens on December 1.")
        }
        return String(localized: "There are no entries for that time.")
    }

    private func load() async {
        isLoading = true
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)]
        let fetched = (try? viewContext.fetch(request)) ?? []
        entries = fetched
        let journal = PeriodReviewJournal(entries: fetched)
        switch route.kind {
        case .year:
            review = await controller.yearReview(route.year, journal: journal)
        case .month, .week:
            review = await controller.monthReview(year: route.year, month: route.month ?? 0, journal: journal)
        }
        isLoading = false
    }
}

struct PeriodReviewDetailView: View {
    let review: PeriodReview
    let entries: [DiaryEntry]
    @ObservedObject private var memory = FridayMemoryPreferences.shared
    @State private var evidence: InsightEvidenceContext?
    @State private var showShare = false
    @State private var openedEntry: PeriodReviewEntryLink?

    private var report: WeeklyReflectionReport { review.report }
    private var stats: PeriodReviewStats { review.stats }
    private var isYear: Bool { review.kind == .year }
    private var showsContent: Bool { report.status != .insufficientData && report.status != .failed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                cover
                if review.touchesHighRiskContent {
                    supportCard
                }
                statsGrid
                if isYear {
                    section(String(localized: "Year in Pixels"), systemImage: "square.grid.3x3.fill") {
                        YearInPixelsView(start: report.periodStart, moodDays: stats.moodDays)
                    }
                    .accessibilityIdentifier("yearInReview.pixels")
                }
                if stats.moodBuckets.contains(where: { $0.averageValence != nil }) {
                    moodSection
                }
                if showsContent {
                    section(String(localized: "Summary", comment: "Review section title"), systemImage: "text.alignleft") {
                        Text(report.summary)
                            .font(OffRecordTypography.bodyMedium)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    peopleAndTopics
                    if !report.themes.isEmpty { themesSection }
                    if !stats.highlights.isEmpty { highlightsSection }
                    if !report.wins.isEmpty {
                        section(String(localized: "Wins", comment: "Weekly reflection section title: things that went well"), systemImage: "sparkles") {
                            bulletList(report.wins)
                        }
                    }
                    if !report.questions.isEmpty { questionsSection }
                }
                if isYear, showsContent {
                    Button {
                        showShare = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))
                    .accessibilityHint("Shows a preview before sharing.")
                    .accessibilityIdentifier("yearInReview.share")
                }
                Text("Based on your words. Not medical advice.")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(OffRecordSpacing.screenX)
            .frame(maxWidth: OffRecordLayout.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(isYear ? "yearInReview.view" : "monthInReview.view")
        .sheet(item: $evidence) { InsightEvidenceSheet(context: $0) }
        .sheet(isPresented: $showShare) {
            YearInReviewShareSheet(content: YearInReviewShareContent(review: review, preferences: memory))
        }
        .navigationDestination(item: $openedEntry) { link in
            EntryDetailView(entry: link.entry)
        }
    }

    // MARK: Sections

    private var cover: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text(review.periodTitle)
                .font(OffRecordTypography.titleLarge)
                .foregroundStyle(OffRecordColor.textHeading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("periodReview.cover")
            Text(report.heroSentence)
                .font(OffRecordTypography.bodyLarge)
                .italic()
                .foregroundStyle(OffRecordColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if report.status == .insufficientData || report.status == .failed {
                Text(report.summary)
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OffRecordSpacing.md) {
                    trustLabel
                    Spacer(minLength: 0)
                    sourcesButton
                }
                VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                    trustLabel
                    sourcesButton
                }
            }
        }
        .padding(OffRecordSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: isYear ? OffRecordColor.surfaceLavender : OffRecordColor.surfaceWarm)
    }

    private var trustLabel: some View {
        Label("Based on ^[\(report.includedEntryIds.count) entry](inflect: true)", systemImage: "book.pages")
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(OffRecordColor.textSage)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sourcesButton: some View {
        Button {
            evidence = InsightEvidenceContext(
                id: "sources-\(review.periodKey)",
                title: String(localized: "Sources"),
                summary: review.periodTitle,
                rationale: String(localized: "Based on your entries from \(review.periodTitle)."),
                entries: entries.filter { entry in entry.id.map(Set(report.includedEntryIds).contains) ?? false }
            )
        } label: {
            Label("Sources", systemImage: "doc.text.magnifyingglass")
                .lineLimit(1)
        }
        .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textSage, fill: OffRecordColor.surfacePrimary.opacity(0.85)))
        .accessibilityIdentifier("periodReview.sources")
    }

    private var supportCard: some View {
        section(String(localized: "Support", comment: "Weekly reflection section title: emotional support resources"), systemImage: "heart") {
            Text("Some entries were heavier than usual. If you need support, reach out to someone you trust. OffRecord isn’t an emergency service.")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            GetSupportButton()
        }
        .accessibilityIdentifier("periodReview.support")
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: OffRecordSpacing.md)], spacing: OffRecordSpacing.md) {
            StatItem(title: String(localized: "Entries", comment: "Review stat label"), value: "\(stats.entryCount)", icon: "book.pages", color: OffRecordColor.textPeach)
            StatItem(title: String(localized: "Days", comment: "Review stat label: days with an entry"), value: "\(stats.activeDays)", icon: "calendar", color: OffRecordColor.textSky)
            StatItem(title: String(localized: "Words", comment: "Stat label: total words written"), value: stats.wordCount.formatted(), icon: "text.word.spacing", color: OffRecordColor.textMint)
            StatItem(title: String(localized: "Minutes Recorded"), value: stats.recordedMinutes.formatted(), icon: "waveform", color: OffRecordColor.textAqua)
        }
        .accessibilityIdentifier("periodReview.stats")
    }

    private var moodPoints: [MoodTrendPoint] {
        stats.moodBuckets.compactMap { bucket in
            guard let valence = bucket.averageValence, let raw = bucket.dominantMood, let mood = Mood(rawValue: raw) else { return nil }
            return MoodTrendPoint(date: bucket.start, valence: valence, mood: mood, entryCount: max(1, bucket.entryCount))
        }
    }

    private var moodSection: some View {
        let phrase = isYear
            ? String(localized: "this year", comment: "Period phrase inside a mood summary sentence")
            : String(localized: "this month", comment: "Period phrase inside a mood summary sentence")
        let summary = MoodTrendNarrator.summary(for: moodPoints, periodPhrase: phrase)
        return section(isYear ? String(localized: "Mood by Month") : String(localized: "Mood by Week"), systemImage: "waveform.path.ecg") {
            Chart(stats.moodBuckets) { bucket in
                if let valence = bucket.averageValence {
                    BarMark(
                        x: .value(isYear ? "Month" : "Week", bucket.start, unit: isYear ? .month : .weekOfYear),
                        y: .value("Mood", valence)
                    )
                    .foregroundStyle((bucket.dominantMood.flatMap(Mood.init(rawValue:)) ?? .none).color)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .chartYScale(domain: -1...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: stats.moodBuckets.map(\.start)) { _ in
                    AxisValueLabel(format: isYear ? .dateTime.month(.narrow) : .dateTime.day())
                }
            }
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            InsightChartSummary(text: summary)
        }
        .accessibilityIdentifier("periodReview.mood")
    }

    private func visible(_ mentions: [PeriodReviewMention]) -> [PeriodReviewMention] {
        mentions.compactMap { mention in
            if let id = mention.nodeID, memory.forgottenIDs.contains(id) { return nil }
            if memory.isForgottenLabel(mention.label) { return nil }
            var copy = mention
            if let id = mention.nodeID, let alias = memory.aliases[id], !alias.isEmpty { copy.label = alias }
            return copy
        }
    }

    @ViewBuilder
    private var peopleAndTopics: some View {
        let people = visible(stats.topPeople)
        let topics = visible(stats.topTopics)
        if !people.isEmpty || !topics.isEmpty {
            section(String(localized: "People and Topics"), systemImage: "person.2") {
                if !people.isEmpty { chipRow(String(localized: "People"), people, tint: OffRecordColor.textPeach) }
                if !topics.isEmpty { chipRow(String(localized: "Topics"), topics, tint: OffRecordColor.textAqua) }
            }
            .accessibilityIdentifier("periodReview.peopleTopics")
        }
    }

    private func chipRow(_ title: String, _ mentions: [PeriodReviewMention], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            Text(title)
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textSecondary)
            FlowLayout(spacing: OffRecordSpacing.sm) {
                ForEach(mentions) { mention in
                    Text("\(mention.label) · \(mention.entryCount)")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(tint)
                        .padding(.horizontal, OffRecordSpacing.md)
                        .padding(.vertical, OffRecordSpacing.xs)
                        .background(tint.opacity(0.12), in: Capsule())
                        .accessibilityLabel(String(AttributedString(localized: "\(mention.label), ^[\(mention.entryCount) entry](inflect: true)").characters))
                }
            }
        }
    }

    private var themesSection: some View {
        section(String(localized: "Themes", comment: "Weekly reflection section title: recurring topics"), systemImage: "tag") {
            ForEach(report.themes) { theme in
                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text(theme.title)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textHeading)
                    Text(theme.summary)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
                .padding(.vertical, OffRecordSpacing.xxs)
            }
        }
    }

    private var highlightsSection: some View {
        section(String(localized: "Entries That Mattered"), systemImage: "star") {
            ForEach(stats.highlights) { highlight in
                Button {
                    if let entry = entries.first(where: { $0.id == highlight.entryId }) {
                        openedEntry = PeriodReviewEntryLink(entry: entry)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                        Text(highlight.date.formatted(date: .abbreviated, time: .omitted))
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                        Text(highlight.snippet)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(reasonText(highlight.reasons))
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textPeach)
                    }
                    .padding(OffRecordSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("periodReview.highlight")
            }
            InsightWhyButton {
                evidence = InsightEvidenceContext(
                    id: "highlights-\(review.periodKey)",
                    title: String(localized: "Entries That Mattered"),
                    summary: review.periodTitle,
                    rationale: String(localized: "Based on stars, Weekly Reflection citations, and top topics."),
                    entries: stats.highlights.compactMap { highlight in entries.first { $0.id == highlight.entryId } }
                )
            }
        }
        .accessibilityIdentifier("periodReview.highlights")
    }

    private func reasonText(_ reasons: [PeriodReviewHighlightReason]) -> String {
        reasons.map { reason -> String in
            switch reason {
            case .starred: return String(localized: "Starred", comment: "Why an entry is in Entries That Mattered")
            case .cited: return String(localized: "In Weekly Reflection", comment: "Why an entry is in Entries That Mattered")
            case .mentions: return String(localized: "Top people and topics", comment: "Why an entry is in Entries That Mattered")
            }
        }
        .joined(separator: " · ")
    }

    private var questionsSection: some View {
        section(isYear ? String(localized: "Looking Ahead") : String(localized: "Questions for Next Month"), systemImage: "questionmark.bubble") {
            bulletList(report.questions)
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: OffRecordSpacing.sm) {
                    Image(systemName: "sparkle")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textSage)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Label(title, systemImage: systemImage)
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textHeading)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary)
    }
}

struct PeriodReviewEntryLink: Identifiable, Hashable {
    let id: NSManagedObjectID
    let entry: DiaryEntry

    init(entry: DiaryEntry) {
        self.id = entry.objectID
        self.entry = entry
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Year in Pixels

/// Every day of a year as a small square colored by that day's mood, in the Timeline calendar's
/// visual language. Data-driven so it can render a stored review and a share image.
struct YearInPixelsView: View {
    let start: Date
    let moodDays: [PeriodReviewMoodDay]
    var columns = 3
    var calendar: Calendar = .current

    private var moodsByDay: [Date: String] {
        Dictionary(moodDays.map { (calendar.startOfDay(for: $0.day), $0.mood) }, uniquingKeysWith: { first, _ in first })
    }

    private var months: [Date] {
        let year = calendar.component(.year, from: start)
        return (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }

    var body: some View {
        let lookup = moodsByDay
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OffRecordSpacing.md), count: columns), spacing: OffRecordSpacing.md) {
            ForEach(months, id: \.self) { month in
                VStack(alignment: .leading, spacing: 4) {
                    Text(month.formatted(.dateTime.month(.abbreviated)))
                        .font(OffRecordTypography.annotation.weight(.semibold))
                        .foregroundStyle(OffRecordColor.textSecondary)
                    monthGrid(month, lookup: lookup)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(AttributedString(localized: "\(month.formatted(.dateTime.month(.wide))), ^[\(daysWithEntries(in: month, lookup: lookup)) day](inflect: true) journaled").characters))
            }
        }
    }

    private func daysWithEntries(in month: Date, lookup: [Date: String]) -> Int {
        lookup.keys.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.count
    }

    private func monthGrid(_ month: Date, lookup: [Date: String]) -> some View {
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: leading) + (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: month) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        return Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<7, id: \.self) { index in
                        if index < row.count, let day = row[index] {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(fill(for: lookup[calendar.startOfDay(for: day)]))
                                .aspectRatio(1, contentMode: .fit)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    private func fill(for mood: String?) -> Color {
        guard let mood else { return OffRecordColor.textTertiary.opacity(0.14) }
        let value = Mood(rawValue: mood) ?? .none
        return value == .none ? OffRecordColor.brandLavender.opacity(0.55) : value.color
    }
}
