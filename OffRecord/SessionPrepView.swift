//
//  SessionPrepView.swift
//  OffRecord
//
//  Pick a date range, see a short factual summary, choose any quotes and
//  what to bring up, then export a PDF, Markdown, or plain-text file.
//  Reached from Insights and from Settings → Backup & Export → Export.
//

import CoreData
import SwiftUI
import os.log

private let sessionPrepLogger = Logger(subsystem: "com.singularity.offrecord", category: "SessionPrep")

enum SessionPrepFormat: String, CaseIterable, Identifiable {
    case pdf
    case markdown
    case plainText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return String(localized: "PDF")
        case .markdown: return String(localized: "Markdown")
        case .plainText: return String(localized: "Plain Text")
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }
}

enum SessionPrepExport {
    /// Writes the document to a temporary file for the share sheet.
    @MainActor
    static func write(_ document: SessionPrepDocument, format: SessionPrepFormat, start: Date, end: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "OffRecord-Session-Prep-\(formatter.string(from: start))-to-\(formatter.string(from: end)).\(format.fileExtension)"
        switch format {
        case .pdf:
            return try PDFExportService.generateDocumentPDF(document, fileName: fileName)
        case .markdown, .plainText:
            let text = format == .markdown ? SessionPrepBuilder.markdown(document) : SessionPrepBuilder.plainText(document)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    /// People Friday knows by name (and their renamed labels), so they can be replaced in the export.
    @MainActor
    static func knownNames() -> [String] {
        let preferences = FridayMemoryPreferences.shared
        return FridayAssistantEngine.shared.knowledgeGraph.nodes.values
            .filter { $0.type == .person }
            .flatMap { [$0.label, preferences.displayName(for: $0)] }
    }
}

struct SessionPrepView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        predicate: DiaryEntry.startedEntryPredicate
    )
    private var fetchedEntries: FetchedResults<DiaryEntry>

    @State private var start: Date = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var end: Date = Date()
    @State private var selectedQuoteIDs: Set<UUID> = []
    @State private var bringUp = ""
    @State private var replaceNames = true
    @State private var format: SessionPrepFormat = .pdf
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showAllQuotes = false
    /// Entries, summary, and preview for the current range, rebuilt only when the range,
    /// the entries, or the names choice change (not on every keystroke).
    @State private var entries: [SessionPrepEntry] = []
    @State private var summary = SessionPrepSummary()
    @State private var previewSections: [SessionPrepDocument.Section] = []

    private var rangeStart: Date { Calendar.current.startOfDay(for: min(start, end)) }
    private var rangeEnd: Date {
        let day = Calendar.current.startOfDay(for: max(start, end))
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? max(start, end)
    }

    private var refreshKey: String {
        var hasher = Hasher()
        for entry in fetchedEntries {
            hasher.combine(entry.objectID)
            hasher.combine(entry.updatedAt)
        }
        return "\(rangeStart.timeIntervalSince1970)-\(rangeEnd.timeIntervalSince1970)-\(replaceNames)-\(hasher.finalize())"
    }

    private var options: SessionPrepOptions {
        SessionPrepOptions(start: rangeStart, end: rangeEnd, selectedQuoteIDs: selectedQuoteIDs, bringUp: bringUp, replaceNames: replaceNames)
    }

    var body: some View {
        let candidates = SessionPrepBuilder.quoteCandidates(entries)
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                datesCard(summary)
                if summary.excludedEntryCount > 0 {
                    supportCard
                }
                summaryCard(summary)
                bringUpCard
                quotesCard(candidates)
                optionsCard
                exportButton(isEmpty: entries.isEmpty)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.screenY)
        }
        .background(OffRecordAppBackground())
        .navigationTitle("Session Prep")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("sessionPrep.view")
        .task(id: refreshKey) { refresh() }
        .sheet(item: Binding(
            get: { exportURL.map { IdentifiableURL(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { item in
            ShareSheet(activityItems: [item.url])
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

    // MARK: - Cards

    private func datesCard(_ summary: SessionPrepSummary) -> some View {
        SettingsCard(
            title: String(localized: "Dates", comment: "Session Prep: date range section"),
            footer: String(AttributedString(localized: "^[\(summary.entryCount) entry](inflect: true) in this range").characters),
            systemImage: "calendar",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfaceBlue
        ) {
            DatePicker("From", selection: $start, in: ...Date(), displayedComponents: .date)
                .accessibilityIdentifier("sessionPrep.from")
            DatePicker("To", selection: $end, in: ...Date(), displayedComponents: .date)
                .accessibilityIdentifier("sessionPrep.to")
        }
    }

    private var supportCard: some View {
        SettingsCard(
            title: String(localized: "Support", comment: "Weekly reflection section title: emotional support resources"),
            systemImage: "heart",
            tint: OffRecordColor.textCoral,
            fill: OffRecordColor.surfacePrimary
        ) {
            Text("Some entries in this range were heavier than usual, so the summary leaves them out. If you need support, reach out to someone you trust. OffRecord isn’t an emergency service.")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            GetSupportButton()
        }
        .accessibilityIdentifier("sessionPrep.support")
    }

    private func summaryCard(_ summary: SessionPrepSummary) -> some View {
        let summarySections = previewSections.filter { $0.style == .bullets }
        return SettingsCard(
            title: String(localized: "Summary", comment: "Session Prep: the generated summary"),
            systemImage: "text.alignleft",
            tint: OffRecordColor.textLavender,
            fill: OffRecordColor.surfaceLavender
        ) {
            ForEach(summarySections, id: \.heading) { section in
                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text(section.heading)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textHeading)
                    ForEach(section.items, id: \.self) { item in
                        Text(item)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("sessionPrep.summary")
    }

    private var bringUpCard: some View {
        SettingsCard(
            title: String(localized: "What I Want to Bring Up", comment: "Session Prep section; written in the person's voice"),
            systemImage: "text.bubble",
            tint: OffRecordColor.textPeach,
            fill: OffRecordColor.surfaceWarm
        ) {
            TextField("Things to talk about", text: $bringUp, axis: .vertical)
                .font(OffRecordTypography.bodyMedium)
                .lineLimit(3...8)
                .padding(OffRecordSpacing.md)
                .background(OffRecordColor.surfacePrimary, in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
                .accessibilityIdentifier("sessionPrep.bringUp")
        }
    }

    private func quotesCard(_ candidates: [SessionPrepEntry]) -> some View {
        let shown = showAllQuotes ? candidates : Array(candidates.prefix(10))
        return SettingsCard(
            title: String(localized: "Quotes", comment: "Session Prep: choose entry excerpts to include"),
            footer: String(localized: "None are included unless you pick them."),
            systemImage: "quote.opening",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfacePrimary
        ) {
            if candidates.isEmpty {
                Text("No entries in this range.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
            ForEach(shown) { entry in
                Toggle(isOn: Binding(
                    get: { selectedQuoteIDs.contains(entry.id) },
                    set: { isOn in
                        if isOn { selectedQuoteIDs.insert(entry.id) } else { selectedQuoteIDs.remove(entry.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                        Text(SessionPrepBuilder.excerpt(entry.quoteText))
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .lineLimit(3)
                    }
                }
                .tint(OffRecordColor.brandSageDark)
                .accessibilityIdentifier("sessionPrep.quote.toggle")
            }
            if candidates.count > shown.count {
                Button(String(AttributedString(localized: "Show ^[\(candidates.count - shown.count) More Entry](inflect: true)").characters)) {
                    showAllQuotes = true
                }
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textAqua)
            }
        }
        .accessibilityIdentifier("sessionPrep.quotes")
    }

    private var optionsCard: some View {
        SettingsCard(
            title: String(localized: "File", comment: "Session Prep: export options"),
            footer: replaceNames
                ? String(localized: "Names are replaced with \u{201C}someone.\u{201D}")
                : String(localized: "Names will be visible in the file."),
            systemImage: "doc.richtext",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfacePrimary
        ) {
            Toggle("Replace Names", isOn: $replaceNames)
                .tint(OffRecordColor.brandSageDark)
                .accessibilityIdentifier("sessionPrep.replaceNames")
            Picker("Format", selection: $format) {
                ForEach(SessionPrepFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sessionPrep.format")
        }
    }

    private func exportButton(isEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            OffRecordPrivacyBadge(title: String(localized: "Only what you see here goes in the file."))
            Button {
                export()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .disabled(isEmpty)
            .accessibilityIdentifier("sessionPrep.export")
        }
    }

    // MARK: - Actions

    private func refresh() {
        entries = fetchedEntries
            .filter { entry in
                guard let date = entry.date ?? entry.createdAt else { return false }
                return date >= rangeStart && date <= rangeEnd
            }
            .compactMap(SessionPrepEntry.init(entry:))
        summary = SessionPrepBuilder.summary(for: entries, start: rangeStart, end: rangeEnd)
        previewSections = SessionPrepBuilder.document(
            entries: entries,
            options: SessionPrepOptions(start: rangeStart, end: rangeEnd, replaceNames: replaceNames),
            knownNames: replaceNames ? SessionPrepExport.knownNames() : []
        ).sections
        // Quotes outside the new range drop out of the selection.
        selectedQuoteIDs.formIntersection(Set(entries.map(\.id)))
    }

    private func export() {
        let document = SessionPrepBuilder.document(
            entries: entries,
            options: options,
            knownNames: replaceNames ? SessionPrepExport.knownNames() : [],
            deviceNoun: DeviceNoun.current
        )
        do {
            exportURL = try SessionPrepExport.write(document, format: format, start: rangeStart, end: rangeEnd)
            HapticManager.shared.entrySaved()
        } catch {
            sessionPrepLogger.error("Session Prep export failed: \(error.localizedDescription, privacy: .public)")
            exportError = String(localized: "Try again.")
            HapticManager.shared.error()
        }
    }
}

/// The Session Prep card on Insights.
struct SessionPrepCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: String(localized: "Session Prep"), systemImage: "list.clipboard", tint: OffRecordColor.textSky)
            Text("A summary of a date range to bring to a session.")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                SessionPrepView()
            } label: {
                Label("Prepare", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))
            .accessibilityIdentifier("insights.sessionPrep.open")
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlue)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.sessionPrep")
    }
}
