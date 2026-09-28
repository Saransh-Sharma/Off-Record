import CoreData
import SwiftUI

struct WeeklyReflectionHomeCard: View {
    let entries: [DiaryEntry]
    var onWrite: (() -> Void)?
    @ObservedObject private var controller = WeeklyReflectionController.shared
    private var entriesSignature: String {
        entries.map { entry in
            let id = entry.id?.uuidString ?? entry.objectID.uriRepresentation().absoluteString
            let updated = entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0
            return "\(id):\(updated)"
        }
        .joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.settings.isEnabled,
               controller.settings.showHomeCard,
               let report = controller.currentReport,
               report.isVisibleOnHome {
                card(for: report)
            }
        }
        .onAppear { refreshUnlessUsingFailedUITestFixture() }
        .onChange(of: entriesSignature) { _, _ in refreshUnlessUsingFailedUITestFixture() }
    }

    private func refreshUnlessUsingFailedUITestFixture() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-WeeklyReflectionFailed"),
              !arguments.contains("-WeeklyReflectionDeleted"),
              !arguments.contains("-WeeklyReflectionDismissed") else { return }
        controller.refreshIfNeeded(entries: entries)
    }

    @ViewBuilder
    private func card(for report: WeeklyReflectionReport) -> some View {
        switch report.status {
        case .insufficientData:
            emptyCard(report)
        case .failed:
            failedCard(report)
        default:
            readyCard(report)
        }
    }

    private func readyCard(_ report: WeeklyReflectionReport) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                trustIcon("sparkles")
                VStack(alignment: .leading, spacing: 5) {
                    NavigationLink {
                        WeeklyReflectionReportView(report: report, entries: entries)
                    } label: {
                        Text("Weekly Reflection")
                            .font(OffRecordTypography.sectionTitle)
                            .foregroundColor(OffRecordColor.textHeading)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weeklyReflection.home.ready")
                    Text("I looked back at ^[\(report.includedEntryIds.count) entry](inflect: true) from this week.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                Spacer()
                Menu {
                    Button("Hide This Week") { controller.dismiss(report) }
                    Button("Change Reminder Time") { OffRecordNavigationRouter.shared.selectedTab = .settings }
                    Button("Settings") { OffRecordNavigationRouter.shared.selectedTab = .settings }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(OffRecordColor.textTertiary)
                        .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .padding(.top, -OffRecordSpacing.md)
                .padding(.trailing, -OffRecordSpacing.md)
                .accessibilityLabel("More")
            }

            NavigationLink {
                WeeklyReflectionReportView(report: report, entries: entries)
            } label: {
                Label("Open", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("weeklyReflection.home.ready.button")
        }
        .padding(18)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    private func emptyCard(_ report: WeeklyReflectionReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                trustIcon("moon.stars")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Not Enough Yet")
                        .font(OffRecordTypography.sectionTitle)
                        .foregroundColor(OffRecordColor.textHeading)
                    Text(notEnoughMessage(report))
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            Button {
                onWrite?()
            } label: {
                Label("Write", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("weeklyReflection.home.empty")
        }
        .padding(18)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
        .accessibilityIdentifier("weeklyReflection.home.empty")
    }

    private func failedCard(_ report: WeeklyReflectionReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn’t Make This Reflection")
                .font(OffRecordTypography.sectionTitle)
                .foregroundColor(OffRecordColor.textHeading)
            Text("Your entries are fine. Try again in a bit.")
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
            Button("Try Again") {
                controller.refreshIfNeeded(entries: entries, force: true)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("weeklyReflection.home.failed")
        }
        .padding(18)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePeach)
        .accessibilityIdentifier("weeklyReflection.home.failed")
    }

    /// How many more entries this week reach a full reflection; falls back to
    /// "a little more" when the entry count is met but the week is still short.
    private func notEnoughMessage(_ report: WeeklyReflectionReport) -> LocalizedStringKey {
        let needed = WeeklyReflectionEligibilityService.fullEntryCount - report.includedEntryIds.count
        guard needed > 0 else { return "Write a little more this week and I’ll put one together." }
        return "Write ^[\(needed) more entry](inflect: true) this week and I’ll put one together."
    }

    private func trustIcon(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(OffRecordColor.backgroundSageTint)
                .frame(width: 42, height: 42)
            Image(systemName: systemName)
                .font(OffRecordTypography.labelLarge)
                .foregroundColor(OffRecordColor.textSage)
        }
    }
}

/// The single Weekly Reflection surface on Insights: this week's report as a
/// featured card, followed by earlier weeks.
struct WeeklyReflectionHistorySection: View {
    let entries: [DiaryEntry]
    @ObservedObject private var controller = WeeklyReflectionController.shared
    @State private var selectedReport: WeeklyReflectionReport?

    private var reports: [WeeklyReflectionReport] { Array(controller.visibleReports.prefix(7)) }

    private var currentWeekReport: WeeklyReflectionReport? {
        reports.first { $0.period.contains(Date()) }
    }

    private var earlierReports: [WeeklyReflectionReport] {
        Array(reports.filter { $0.id != currentWeekReport?.id }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: "Weekly Reflection", systemImage: "calendar.badge.clock", tint: OffRecordColor.textSage)

            if reports.isEmpty {
                InsightChartEmptyState(
                    systemImage: "moon.stars",
                    message: "After \(WeeklyReflectionEligibilityService.fullEntryCount) entries this week, I’ll put a reflection here."
                )
            } else {
                if let currentWeekReport {
                    Button {
                        selectedReport = currentWeekReport
                    } label: {
                        currentWeekCard(currentWeekReport)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weeklyReflection.history.row")
                }

                if !earlierReports.isEmpty {
                    Text("Earlier Weeks")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .padding(.top, OffRecordSpacing.xs)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(earlierReports.enumerated()), id: \.element.id) { index, report in
                        if index > 0 {
                            Divider().overlay(OffRecordColor.hairline)
                        }
                        Button {
                            selectedReport = report
                        } label: {
                            historyRow(report)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weeklyReflection.history.row")
                    }
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary)
        .onAppear { controller.refreshIfNeeded(entries: entries) }
        .navigationDestination(item: $selectedReport) { report in
            WeeklyReflectionReportView(report: report, entries: entries)
        }
    }

    private func currentWeekCard(_ report: WeeklyReflectionReport) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(OffRecordTypography.badgeLabel)
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(OffRecordColor.textSage)
                Spacer(minLength: OffRecordSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textTertiary)
                    .accessibilityHidden(true)
            }

            Text(dateRange(report))
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textPrimary)

            if report.status.showsReflectionContent {
                Text(report.heroSentence)
                    .font(OffRecordTypography.bodySmall)
                    .italic()
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OffRecordSpacing.md) { reportMeta(report) }
                    VStack(alignment: .leading, spacing: OffRecordSpacing.xs) { reportMeta(report) }
                }
            } else {
                Text(statusLabel(report))
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OffRecordColor.surfaceMint, in: RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                .stroke(OffRecordColor.borderSage, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous))
    }

    @ViewBuilder
    private func reportMeta(_ report: WeeklyReflectionReport) -> some View {
        Group {
            Label("^[\(report.includedEntryIds.count) entry](inflect: true)", systemImage: "book.pages")
        }
        .font(OffRecordTypography.labelSmall)
        .foregroundStyle(OffRecordColor.textSage)
    }

    private func historyRow(_ report: WeeklyReflectionReport) -> some View {
        let themes = report.themes.map(\.title).prefix(3).joined(separator: " · ")
        return HStack(alignment: .center, spacing: OffRecordSpacing.md) {
            Image(systemName: report.savedTakeaway == nil ? "doc.text" : "bookmark.fill")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(report.savedTakeaway == nil ? OffRecordColor.textAqua : OffRecordColor.textSage)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text(dateRange(report))
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                Text(themes.isEmpty ? statusLabel(report) : themes)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func statusLabel(_ report: WeeklyReflectionReport) -> String {
        switch report.status {
        case .insufficientData: return "Not enough entries yet"
        case .failed: return "Couldn’t be made"
        default: return String(AttributedString(localized: "^[\(report.includedEntryIds.count) entry](inflect: true)").characters)
        }
    }
}

private extension WeeklyReflectionStatus {
    var showsReflectionContent: Bool {
        switch self {
        case .insufficientData, .failed: return false
        default: return true
        }
    }
}

/// Daily mood points for the entries a report was built from.
@MainActor
enum WeeklyReflectionArcData {
    static func points(for report: WeeklyReflectionReport, entries: [DiaryEntry], calendar: Calendar = .current) -> [MoodTrendPoint] {
        let included = Set(report.includedEntryIds)
        var byDay: [Date: [JournalEntrySnapshot]] = [:]
        for entry in entries {
            guard let date = entry.date ?? entry.createdAt, report.period.contains(date) else { continue }
            if !included.isEmpty, let id = entry.id, !included.contains(id) { continue }
            byDay[calendar.startOfDay(for: date), default: []].append(JournalEntrySnapshot(entry: entry))
        }
        return InsightChartsSnapshot.dailyMoodPoints(entriesByDay: byDay)
    }
}

struct WeeklyReflectionReportView: View {
    let report: WeeklyReflectionReport
    let entries: [DiaryEntry]
    @ObservedObject private var controller = WeeklyReflectionController.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var takeawayText: String = ""
    @State private var showSources = false
    @State private var showExport = false
    @State private var showDeleteConfirmation = false
    @State private var saveCount = 0
    @State private var arcPoints: [MoodTrendPoint] = []

    private var displayedReport: WeeklyReflectionReport {
        controller.report(id: report.id) ?? report
    }

    private var trimmedTakeaway: String {
        takeawayText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var takeawayIsSaved: Bool {
        !trimmedTakeaway.isEmpty && displayedReport.savedTakeaway == trimmedTakeaway
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                cover
                if displayedReport.safetyLevel == .highRiskExcluded {
                    supportCard
                }
                sectionCard(title: "Summary", systemImage: "text.alignleft") {
                    Text(displayedReport.summary)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundStyle(OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if displayedReport.emotionalArc != nil || !arcPoints.isEmpty {
                    arcSection
                }
                if !displayedReport.themes.isEmpty {
                    themesSection
                }
                if !displayedReport.wins.isEmpty {
                    sectionCard(title: "Wins", systemImage: "sparkles") {
                        bulletList(displayedReport.wins, symbol: "sparkle", tint: OffRecordColor.textSage)
                    }
                }
                if !displayedReport.frictions.isEmpty {
                    sectionCard(title: "What Was Hard", systemImage: "cloud") {
                        bulletList(displayedReport.frictions, symbol: "circle.fill", tint: OffRecordColor.textLavender, symbolScale: .small)
                    }
                }
                if !displayedReport.questions.isEmpty {
                    questionsSection
                }
                takeawaySection
                exportButton
                Text("Based on your words. Not medical advice.")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("weeklyReflection.disclaimer")
            }
            .padding(OffRecordSpacing.screenX)
            .frame(maxWidth: OffRecordLayout.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(OffRecordAppBackground().ignoresSafeArea())
        .navigationTitle("Weekly Reflection")
        .navigationBarTitleDisplayMode(.inline)
        // A focused reading view, like an open entry.
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            controller.markSeen(displayedReport)
            takeawayText = displayedReport.savedTakeaway ?? suggestedTakeaway
            arcPoints = WeeklyReflectionArcData.points(for: displayedReport, entries: sourceEntries)
        }
        .sheet(isPresented: $showSources) {
            WeeklyReflectionSourcesSheet(report: displayedReport, entries: entries)
        }
        .sheet(isPresented: $showExport) {
            WeeklyReflectionExportSheet(report: displayedReport)
        }
        .confirmationDialog(
            "Delete Reflection?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Reflection", role: .destructive) {
                controller.delete(displayedReport)
                dismiss()
            }
            .accessibilityIdentifier("weeklyReflection.delete.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your entries won’t be affected.")
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("weeklyReflection.menu.export")
                    Button {
                        controller.dismiss(displayedReport)
                        dismiss()
                    } label: {
                        Label("Hide This Week", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("weeklyReflection.menu.dismiss")
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Reflection", systemImage: "trash")
                    }
                    .accessibilityIdentifier("weeklyReflection.menu.delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                }
                .accessibilityIdentifier("weeklyReflection.report.menu")
            }
        }
    }

    /// Entries passed in, or a fetch of started entries when the caller had none.
    private var sourceEntries: [DiaryEntry] {
        if !entries.isEmpty { return entries }
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)]
        return (try? viewContext.fetch(request)) ?? []
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text(dateRange(displayedReport))
                .font(OffRecordTypography.titleLarge)
                .foregroundStyle(OffRecordColor.textHeading)
                .accessibilityIdentifier("weeklyReflection.report.cover")
                .accessibilityAddTraits(.isHeader)
            Text(displayedReport.heroSentence)
                .font(OffRecordTypography.bodyLarge)
                .foregroundStyle(OffRecordColor.textPrimary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

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
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    private var trustLabel: some View {
        Label("Based on ^[\(displayedReport.includedEntryIds.count) entry](inflect: true)", systemImage: "book.pages")
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(OffRecordColor.textSage)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The one entry point to the sources sheet.
    private var sourcesButton: some View {
        Button {
            showSources = true
        } label: {
            Label("Sources", systemImage: "doc.text.magnifyingglass")
                .lineLimit(1)
        }
        .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textSage, fill: OffRecordColor.surfacePrimary.opacity(0.85)))
        .accessibilityIdentifier("weeklyReflection.sources.openSheet")
        .accessibilityHint("Shows the entries used and lets you hide some.")
    }

    private var supportCard: some View {
        sectionCard(title: "Support", systemImage: "heart") {
            Text("Some entries this week were heavier than usual. If you need support, reach out to someone you trust. OffRecord isn’t an emergency service.")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("weeklyReflection.support")
    }

    private var arcSummary: String {
        if let arc = displayedReport.emotionalArc, !arc.description.isEmpty {
            return arc.description
        }
        return MoodTrendNarrator.summary(for: arcPoints, periodPhrase: "this week")
    }

    private var arcSection: some View {
        sectionCard(title: "Mood", systemImage: "waveform.path.ecg") {
            if let arc = displayedReport.emotionalArc {
                Text(arc.label)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textHeading)
            }
            WeeklyMoodArcChart(
                points: arcPoints,
                periodStart: displayedReport.periodStart,
                periodEnd: displayedReport.periodEnd,
                summary: arcSummary
            )
            InsightChartSummary(text: arcSummary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weeklyReflection.arc")
    }

    private var themesSection: some View {
        sectionCard(title: "Themes", systemImage: "tag") {
            ForEach(displayedReport.themes) { theme in
                VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                    Text(theme.title)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textHeading)
                    Text(theme.summary)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let quote = theme.evidenceRefs.first?.quote {
                        HStack(alignment: .top, spacing: OffRecordSpacing.sm) {
                            Image(systemName: "quote.opening")
                                .font(OffRecordTypography.labelSmall)
                                .foregroundStyle(OffRecordColor.textPeach)
                                .accessibilityHidden(true)
                            Text(quote)
                                .font(OffRecordTypography.metadata)
                                .foregroundStyle(OffRecordColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(OffRecordSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("From your entry: \(quote)")
                    }
                }
                .padding(.vertical, OffRecordSpacing.xs)
            }
        }
    }

    private var questionsSection: some View {
        sectionCard(title: "Questions for Next Week", systemImage: "questionmark.bubble") {
            VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
                ForEach(Array(displayedReport.questions.enumerated()), id: \.offset) { index, question in
                    HStack(alignment: .firstTextBaseline, spacing: OffRecordSpacing.sm) {
                        Image(systemName: index < 50 ? "\(index + 1).circle.fill" : "circle.fill")
                            .font(OffRecordTypography.labelLarge)
                            .foregroundStyle(OffRecordColor.textAqua)
                            .accessibilityHidden(true)
                        Text(question)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Question \(index + 1): \(question)")
                }
            }
        }
    }

    private var takeawaySection: some View {
        sectionCard(title: "Takeaway", systemImage: "bookmark") {
            TextField("What do you want to remember?", text: $takeawayText, axis: .vertical)
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OffRecordColor.textPrimary)
                .lineLimit(2...5)
                .padding(OffRecordSpacing.md)
                .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous)
                        .stroke(OffRecordColor.borderSoft, lineWidth: 1)
                )
                .accessibilityIdentifier("weeklyReflection.takeaway.textField")

            saveTakeawayButton
                .offRecordAnimation(OffRecordMotion.fade, value: takeawayIsSaved)
        }
    }

    private var saveTakeawayButton: some View {
        Button {
            controller.saveTakeaway(takeawayText, for: displayedReport)
            saveCount += 1
        } label: {
            Label(takeawayIsSaved ? "Saved" : "Save", systemImage: takeawayIsSaved ? "checkmark" : "bookmark.fill")
        }
        .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandPlum))
        .disabled(trimmedTakeaway.isEmpty)
        .opacity(trimmedTakeaway.isEmpty ? 0.5 : 1)
        .accessibilityIdentifier("weeklyReflection.takeaway.save")
    }

    private var exportButton: some View {
        Button {
            showExport = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))
        .accessibilityIdentifier("weeklyReflection.export.open")
    }

    private func bulletList(_ items: [String], symbol: String, tint: Color, symbolScale: Image.Scale = .medium) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: OffRecordSpacing.sm) {
                    Image(systemName: symbol)
                        .font(OffRecordTypography.labelSmall)
                        .imageScale(symbolScale)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
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

    private var suggestedTakeaway: String {
        displayedReport.themes.first?.title ?? displayedReport.heroSentence
    }
}

private struct WeeklyReflectionSourcesSheet: View {
    let report: WeeklyReflectionReport
    let entries: [DiaryEntry]
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var controller = WeeklyReflectionController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var includedSelection: Set<UUID> = []
    @State private var selectedEntry: IdentifiableEntry?

    private var availableEntries: [DiaryEntry] {
        sourceEntries.filter { entry in
            guard entry.id != nil else { return false }
            return report.period.contains(entry.date ?? entry.createdAt ?? .distantPast)
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private var sourceEntries: [DiaryEntry] {
        if !entries.isEmpty { return entries }
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)]
        return (try? viewContext.fetch(request)) ?? []
    }

    private var availableEntryIDs: Set<UUID> {
        Set(availableEntries.compactMap(\.id))
    }

    private var selectedHiddenIDs: [UUID] {
        Array(availableEntryIDs.subtracting(includedSelection))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(availableEntries, id: \.objectID) { entry in
                        sourceRow(entry)
                    }
                } header: {
                    Text("Included")
                } footer: {
                    Text("Hidden entries are left out of this reflection only.")
                }
                if !report.hiddenEntryIds.isEmpty || !report.unavailableEntryIds.isEmpty {
                    Section("Hidden") {
                        Text("\(report.hiddenEntryIds.count) hidden · \(report.unavailableEntryIds.count) deleted")
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        controller.regenerate(report: report, hiding: selectedHiddenIDs, entries: availableEntries)
                        dismiss()
                    }
                    .disabled(Set(report.hiddenEntryIds) == Set(selectedHiddenIDs))
                    .accessibilityIdentifier("weeklyReflection.sources.update")
                }
            }
            .navigationDestination(item: $selectedEntry) { item in
                EntryDetailView(entry: item.entry)
            }
        }
        .onAppear {
            includedSelection = availableEntryIDs.subtracting(report.hiddenEntryIds)
        }
    }

    private func sourceRow(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedEntry = IdentifiableEntry(entry: entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.date ?? Date(), style: .date)
                        .foregroundColor(OffRecordColor.textPrimary)
                    Text(sourceSummary(entry))
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("weeklyReflection.sources.openEntry")

            if let id = entry.id {
                Toggle("Include", isOn: Binding(
                    get: { includedSelection.contains(id) },
                    set: { isIncluded in
                        if isIncluded {
                            includedSelection.insert(id)
                        } else {
                            includedSelection.remove(id)
                        }
                    }
                ))
                .font(OffRecordTypography.metadata)
                .accessibilityIdentifier("weeklyReflection.sources.includeToggle")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weeklyReflection.sources.entry")
    }

    private func sourceSummary(_ entry: DiaryEntry) -> String {
        let words = String(AttributedString(localized: "^[\(entry.startedEntryWordCount) word](inflect: true)").characters)
        if entry.hasStartedEntryAudio { return "Recording · \(words)" }
        if entry.hasStartedEntryPhotos { return "Photo · \(words)" }
        return "Text · \(words)"
    }
}

private struct IdentifiableEntry: Identifiable, Hashable {
    let id: NSManagedObjectID
    let entry: DiaryEntry

    init(entry: DiaryEntry) {
        self.id = entry.objectID
        self.entry = entry
    }

    static func == (lhs: IdentifiableEntry, rhs: IdentifiableEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct WeeklyReflectionExportSheet: View {
    let report: WeeklyReflectionReport
    @Environment(\.dismiss) private var dismiss
    @State private var format: WeeklyReflectionExportService.Format = .markdown
    @State private var includeQuotes = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Quotes from Entries", isOn: $includeQuotes)
                        .accessibilityIdentifier("weeklyReflection.export.includeQuotes")
                } header: {
                    Text("Include")
                } footer: {
                    Text("Exports never include full entries.")
                }
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(WeeklyReflectionExportService.Format.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .accessibilityIdentifier("weeklyReflection.export.format")
                }
                Section {
                    Button("Preview") {
                        do {
                            exportURL = try WeeklyReflectionExportService.export(report: report, format: format, includeQuotes: includeQuotes)
                        } catch {
                            exportError = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("weeklyReflection.export.preview")
                }
            }
            .navigationTitle("Export Reflection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: Binding(
            get: { exportURL.map { IdentifiableURL(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { item in
            #if os(iOS)
            ShareSheet(activityItems: [item.url])
            #else
            Text(item.url.absoluteString)
            #endif
        }
        .alert("Couldn’t Export", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }
}

/// "Sep 22 – 28", with the year added for weeks outside the current year.
private func dateRange(_ report: WeeklyReflectionReport) -> String {
    let end = max(report.periodEnd, report.periodStart)
    let range = report.periodStart..<end
    let isThisYear = Calendar.current.isDate(report.periodStart, equalTo: Date(), toGranularity: .year)
        && Calendar.current.isDate(end, equalTo: Date(), toGranularity: .year)
    return isThisYear
        ? range.formatted(.interval.month(.abbreviated).day())
        : range.formatted(.interval.month(.abbreviated).day().year())
}
