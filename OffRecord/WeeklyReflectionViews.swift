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
        guard !ProcessInfo.processInfo.arguments.contains("-WeeklyReflectionFailed") else { return }
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
                        Text(report.eligibility == .light ? "A small reflection" : "Your weekly reflection is ready")
                            .font(OffRecordTypography.sectionTitle)
                            .foregroundColor(OffRecordColor.textHeading)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weeklyReflection.home.ready")
                    Text("A private look back at what showed up this week.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                Spacer()
                Menu {
                    Button("Hide this week") { controller.dismiss(report) }
                    Button("Change reminder time") { OffRecordNavigationRouter.shared.selectedTab = .settings }
                    Button("Privacy settings") { OffRecordNavigationRouter.shared.selectedTab = .settings }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(OffRecordColor.textTertiary)
                }
                .accessibilityLabel("Weekly reflection options")
            }

            HStack(spacing: 8) {
                Label("\(report.includedEntryIds.count) entries", systemImage: "book.pages")
                Label("Generated on-device", systemImage: "lock.shield")
            }
            .font(OffRecordTypography.labelSmall)
            .foregroundColor(OffRecordColor.textSage)

            NavigationLink {
                WeeklyReflectionReportView(report: report, entries: entries)
            } label: {
                Label("View reflection", systemImage: "arrow.right")
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
                    Text("No reflection yet")
                        .font(OffRecordTypography.sectionTitle)
                        .foregroundColor(OffRecordColor.textHeading)
                    Text("Write a little more this week and OffRecord will prepare a private reflection.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            Button {
                onWrite?()
            } label: {
                Label("Write a note", systemImage: "square.and.pencil")
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
            Text("Reflection couldn't be created")
                .font(OffRecordTypography.sectionTitle)
                .foregroundColor(OffRecordColor.textHeading)
            Text("Your entries are safe. OffRecord couldn't prepare this reflection right now.")
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
            Button("Try again") {
                controller.refreshIfNeeded(entries: entries, force: true)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("weeklyReflection.home.failed")
        }
        .padding(18)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePeach)
        .accessibilityIdentifier("weeklyReflection.home.failed")
    }

    private func trustIcon(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(OffRecordColor.backgroundSageTint)
                .frame(width: 42, height: 42)
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(OffRecordColor.textSage)
        }
    }
}

struct WeeklyReflectionHistorySection: View {
    let entries: [DiaryEntry]
    @ObservedObject private var controller = WeeklyReflectionController.shared
    @State private var selectedReport: WeeklyReflectionReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Reflections", systemImage: "calendar")
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundColor(OffRecordColor.textHeading)
                Spacer()
            }

            if controller.visibleReports.isEmpty {
                Text("Weekly reflections will appear here after OffRecord has enough entries to review.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textSecondary)
            } else {
                ForEach(controller.visibleReports.prefix(6)) { report in
                    Button {
                        selectedReport = report
                    } label: {
                        historyRow(report)
                    }
                    .buttonStyle(.plain)
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

    private func historyRow(_ report: WeeklyReflectionReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.savedTakeaway == nil ? "doc.text" : "bookmark.fill")
                .foregroundColor(report.savedTakeaway == nil ? OffRecordColor.textAqua : OffRecordColor.textSage)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(dateRange(report))
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordColor.textPrimary)
                Text(report.themes.map(\.title).prefix(3).joined(separator: " · ").isEmpty ? statusLabel(report) : report.themes.map(\.title).prefix(3).joined(separator: " · "))
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(OffRecordTypography.metadata)
                .foregroundColor(OffRecordColor.textTertiary)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("weeklyReflection.history.row")
    }

    private func statusLabel(_ report: WeeklyReflectionReport) -> String {
        switch report.status {
        case .insufficientData: return "Not enough entries"
        case .failed: return "Could not create"
        default: return "\(report.includedEntryIds.count) entries"
        }
    }
}

struct WeeklyReflectionReportView: View {
    let report: WeeklyReflectionReport
    let entries: [DiaryEntry]
    @ObservedObject private var controller = WeeklyReflectionController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var takeawayText: String = ""
    @State private var showSources = false
    @State private var showExport = false

    private var displayedReport: WeeklyReflectionReport {
        controller.report(id: report.id) ?? report
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cover
                if displayedReport.safetyLevel == .highRiskExcluded {
                    supportCard
                }
                sectionCard(title: "Summary", systemImage: "text.alignleft") {
                    Text(displayedReport.summary)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundColor(OffRecordColor.textPrimary)
                }
                if let arc = displayedReport.emotionalArc {
                    sectionCard(title: "Emotional arc", systemImage: "waveform.path.ecg") {
                        Text(arc.label)
                            .font(OffRecordTypography.labelMedium)
                            .foregroundColor(OffRecordColor.textHeading)
                        Text(arc.description)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
                themesSection
                listSection(title: "Small wins", systemImage: "sparkles", items: displayedReport.wins)
                listSection(title: "What felt heavy", systemImage: "cloud", items: displayedReport.frictions)
                questionsSection
                takeawaySection
                actionRow
            }
            .padding(OffRecordSpacing.screenX)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(OffRecordColor.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Weekly Reflection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            controller.markSeen(displayedReport)
            takeawayText = displayedReport.savedTakeaway ?? suggestedTakeaway
        }
        .sheet(isPresented: $showSources) {
            WeeklyReflectionSourcesSheet(report: displayedReport, entries: entries)
        }
        .sheet(isPresented: $showExport) {
            WeeklyReflectionExportSheet(report: displayedReport)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export") { showExport = true }
                        .accessibilityIdentifier("weeklyReflection.menu.export")
                    Button("Privacy & sources") { showSources = true }
                        .accessibilityIdentifier("weeklyReflection.menu.sources")
                    Button("Dismiss this week") {
                        controller.dismiss(displayedReport)
                        dismiss()
                    }
                    .accessibilityIdentifier("weeklyReflection.menu.dismiss")
                    Button("Delete report", role: .destructive) {
                        controller.delete(displayedReport)
                        dismiss()
                    }
                    .accessibilityIdentifier("weeklyReflection.menu.delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("weeklyReflection.report.menu")
            }
        }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Week in Review")
                .font(OffRecordTypography.titleLarge)
                .foregroundColor(OffRecordColor.textHeading)
                .accessibilityIdentifier("weeklyReflection.report.cover")
            Text(dateRange(displayedReport))
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
            Label("Generated on-device · \(displayedReport.includedEntryIds.count) entries included", systemImage: "lock.shield.fill")
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textSage)
            Text("\"\(displayedReport.heroSentence)\"")
                .font(OffRecordTypography.bodyLarge)
                .foregroundColor(OffRecordColor.textPrimary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    private var supportCard: some View {
        sectionCard(title: "Support", systemImage: "heart") {
            Text("Some entries this week seemed heavier than usual. OffRecord is not emergency support, but you may want to reach out to someone you trust.")
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .accessibilityIdentifier("weeklyReflection.support")
    }

    private var themesSection: some View {
        sectionCard(title: "Key themes", systemImage: "tag") {
            ForEach(displayedReport.themes) { theme in
                VStack(alignment: .leading, spacing: 8) {
                    Text(theme.title)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundColor(OffRecordColor.textHeading)
                    Text(theme.summary)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                    if let quote = theme.evidenceRefs.first?.quote {
                        Text("\"\(quote)\"")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: OffRecordRadius.md).fill(OffRecordColor.surfaceWarm))
                    }
                }
                .padding(.vertical, 6)
            }
            Button("View sources") { showSources = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("weeklyReflection.sources.openSheet")
        }
    }

    private var questionsSection: some View {
        sectionCard(title: "Questions for next week", systemImage: "questionmark.bubble") {
            ForEach(displayedReport.questions, id: \.self) { question in
                Text("○ \(question)")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var takeawaySection: some View {
        sectionCard(title: "Save a takeaway", systemImage: "bookmark") {
            TextField("What do you want to remember?", text: $takeawayText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .accessibilityIdentifier("weeklyReflection.takeaway.textField")
            Button("Save takeaway") {
                controller.saveTakeaway(takeawayText, for: displayedReport)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("weeklyReflection.takeaway.save")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                showSources = true
            } label: {
                Label("Privacy & sources", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("weeklyReflection.sources.openSheet")

            Button {
                showExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("weeklyReflection.export.open")
        }
    }

    private func listSection(title: String, systemImage: String, items: [String]) -> some View {
        sectionCard(title: title, systemImage: systemImage) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text("\(index + 1). \(item)")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(OffRecordTypography.sectionTitle)
                .foregroundColor(OffRecordColor.textHeading)
            content()
        }
        .padding(16)
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
                Section("Privacy") {
                    Label("Generated locally", systemImage: "lock.shield.fill")
                    Text("Nothing was sent off your device. Hidden entries only affect this weekly reflection.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                Section("Available Sources") {
                    ForEach(availableEntries, id: \.objectID) { entry in
                        sourceRow(entry)
                    }
                }
                if !report.hiddenEntryIds.isEmpty || !report.unavailableEntryIds.isEmpty {
                    Section("Excluded") {
                        Text("\(report.hiddenEntryIds.count) hidden · \(report.unavailableEntryIds.count) unavailable")
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
            .navigationTitle("Privacy & Sources")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        controller.regenerate(report: report, hiding: selectedHiddenIDs, entries: entries)
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
                Toggle("Include in regenerated report", isOn: Binding(
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
        if entry.hasStartedEntryAudio { return "Voice note · \(entry.startedEntryWordCount) words" }
        if entry.hasStartedEntryPhotos { return "Photo note · \(entry.startedEntryWordCount) words" }
        return "Text entry · \(entry.startedEntryWordCount) words"
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
                Section("Include") {
                    Toggle("Source quotes", isOn: $includeQuotes)
                        .accessibilityIdentifier("weeklyReflection.export.includeQuotes")
                    Text("Source quotes are off by default. The export never includes full journal entries.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
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
                    Button("Preview export") {
                        do {
                            exportURL = try WeeklyReflectionExportService.export(report: report, format: format, includeQuotes: includeQuotes)
                        } catch {
                            exportError = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("weeklyReflection.export.preview")
                } footer: {
                    Text("A short reflection you can bring into a conversation. It does not include your full journal.")
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
        .alert("Export error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }
}

private func dateRange(_ report: WeeklyReflectionReport) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return "\(formatter.string(from: report.periodStart)) - \(formatter.string(from: report.periodEnd))"
}
