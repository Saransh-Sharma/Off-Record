//
//  JournalImportView.swift
//  OffRecord
//
//  Settings → Import: pick another app's export, see what will be added,
//  then import it.
//

import CoreData
import SwiftUI
import os.log

private let importViewLogger = Logger(subsystem: "com.singularity.offrecord", category: "JournalImport")

struct JournalImportView: View {
    @Environment(\.managedObjectContext) private var viewContext

    private enum Phase {
        case choosing
        case reading(JournalImportFormat)
        case preview(JournalImportPreview)
        case importing(JournalImportPreview, Double)
        case done(JournalImportSummary)
    }

    @State private var phase: Phase = .choosing
    @State private var pickerFormat: JournalImportFormat?
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var scopedURLs: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                switch phase {
                case .choosing:
                    sourcesCard
                case .reading:
                    readingCard
                case .preview(let preview):
                    previewCard(preview)
                case .importing(let preview, let progress):
                    importingCard(preview, progress: progress)
                case .done(let summary):
                    resultCard(summary)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.screenY)
        }
        .background(OffRecordAppBackground())
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("import.view")
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: pickerFormat?.allowedContentTypes ?? [.data],
            allowsMultipleSelection: pickerFormat?.allowsMultipleSelection ?? false
        ) { result in
            handlePicked(result)
        }
        .alert("Couldn’t Import", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear(perform: releaseScopedURLs)
    }

    // MARK: - Choosing

    private var sourcesCard: some View {
        SettingsCard(
            title: String(localized: "Import From", comment: "Import screen: list of apps to import from"),
            footer: String(localized: "Entries you’ve already imported are skipped."),
            systemImage: "square.and.arrow.down.on.square",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfaceBlue
        ) {
            ForEach(JournalImportFormat.allCases) { format in
                Button {
                    pickerFormat = format
                    showPicker = true
                    HapticManager.shared.buttonTap()
                } label: {
                    SettingsActionRow(systemImage: format.systemImage, title: format.title, subtitle: format.subtitle, tint: OffRecordColor.textSky)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("import.source.\(format.rawValue)")
            }
        }
    }

    private var readingCard: some View {
        HStack(spacing: OffRecordSpacing.md) {
            ProgressView()
            Text("Reading…")
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OffRecordColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary)
    }

    // MARK: - Preview

    private func previewCard(_ preview: JournalImportPreview) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            SettingsCard(
                title: preview.format.title,
                subtitle: preview.dateRange.map(Self.rangeText),
                systemImage: preview.format.systemImage,
                tint: OffRecordColor.textSky,
                fill: OffRecordColor.surfaceBlue
            ) {
                SettingsRow(systemImage: "book.pages", title: Self.count(preview.newDrafts.count, "entry"), subtitle: String(AttributedString(localized: "On ^[\(preview.dayCount) day](inflect: true)").characters), tint: OffRecordColor.textSky)
                if preview.photoCount > 0 {
                    SettingsRow(systemImage: "photo.on.rectangle", title: Self.count(preview.photoCount, "photo"), subtitle: String(localized: "Up to \(JournalImportService.maximumPhotosPerEntry) per day"), tint: OffRecordColor.textSky)
                }
                if preview.duplicateCount > 0 {
                    SettingsRow(systemImage: "checkmark.circle", title: String(AttributedString(localized: "^[\(preview.duplicateCount) entry](inflect: true) already imported").characters), tint: OffRecordColor.textSage)
                }
                if !preview.skipped.isEmpty {
                    skippedList(preview.skipped)
                }
            }
            .accessibilityIdentifier("import.preview")

            Text("Entries on a day you already wrote are added to that day.")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                startImport(preview)
            } label: {
                Text("Import ^[\(preview.newDrafts.count) Entry](inflect: true)")
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .disabled(preview.newDrafts.isEmpty)
            .accessibilityIdentifier("import.confirm")

            Button("Choose Another File") {
                releaseScopedURLs()
                phase = .choosing
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
        }
    }

    private func skippedList(_ items: [ImportSkippedItem]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                ForEach(items.prefix(50)) { item in
                    Text("\(item.origin) · \(item.reasonText)")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if items.count > 50 {
                    Text("\(items.count - 50) more")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, OffRecordSpacing.xs)
        } label: {
            Label(String(AttributedString(localized: "^[\(items.count) item](inflect: true) skipped").characters), systemImage: "exclamationmark.circle")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textPrimary)
        }
        .tint(OffRecordColor.textSecondary)
        .accessibilityIdentifier("import.preview.skipped")
    }

    private func importingCard(_ preview: JournalImportPreview, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text("Importing…")
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textHeading)
            ProgressView(value: progress)
                .tint(OffRecordColor.brandPlum)
            Text(Self.count(preview.newDrafts.count, "entry"))
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary)
    }

    // MARK: - Result

    private func resultCard(_ summary: JournalImportSummary) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            SettingsCard(
                title: String(localized: "Import Complete"),
                systemImage: "checkmark.circle.fill",
                tint: OffRecordColor.textSage,
                fill: OffRecordColor.surfaceSage
            ) {
                SettingsRow(
                    systemImage: "book.pages",
                    title: String(AttributedString(localized: "^[\(summary.entriesAdded) entry](inflect: true) added").characters),
                    subtitle: String(AttributedString(localized: "On ^[\(summary.daysTouched) day](inflect: true)").characters),
                    tint: OffRecordColor.textSage
                )
                if summary.photosAdded > 0 {
                    SettingsRow(systemImage: "photo.on.rectangle", title: String(AttributedString(localized: "^[\(summary.photosAdded) photo](inflect: true) added").characters), tint: OffRecordColor.textSage)
                }
                if summary.photosOverLimit > 0 {
                    SettingsRow(systemImage: "photo.badge.exclamationmark", title: String(AttributedString(localized: "^[\(summary.photosOverLimit) photo](inflect: true) left out").characters), subtitle: String(localized: "Each day holds up to \(JournalImportService.maximumPhotosPerEntry) photos."), tint: OffRecordColor.textPeach)
                }
                if summary.photosUnreadable > 0 {
                    SettingsRow(systemImage: "photo.badge.exclamationmark", title: String(AttributedString(localized: "^[\(summary.photosUnreadable) photo](inflect: true) couldn’t be read").characters), tint: OffRecordColor.textPeach)
                }
                if summary.duplicatesSkipped > 0 {
                    SettingsRow(systemImage: "checkmark.circle", title: String(AttributedString(localized: "^[\(summary.duplicatesSkipped) entry](inflect: true) already imported").characters), tint: OffRecordColor.textSage)
                }
                if summary.itemsSkipped > 0 {
                    SettingsRow(systemImage: "exclamationmark.circle", title: String(AttributedString(localized: "^[\(summary.itemsSkipped) item](inflect: true) skipped").characters), tint: OffRecordColor.textSecondary)
                }
            }
            .accessibilityIdentifier("import.result")

            Button("Import More") {
                phase = .choosing
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
        }
    }

    // MARK: - Actions

    private func handlePicked(_ result: Result<[URL], Error>) {
        guard let format = pickerFormat else { return }
        switch result {
        case .failure(let error):
            importViewLogger.error("Import picker failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = JournalImportError.unreadable.message
        case .success(let urls):
            guard !urls.isEmpty else { return }
            releaseScopedURLs()
            // Folders and ZIPs are read lazily (photos during import), so access stays open until the screen closes.
            scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
            phase = .reading(format)
            Task { await read(urls: urls, format: format) }
        }
    }

    private func read(urls: [URL], format: JournalImportFormat) async {
        let outcome: Result<(any JournalImportSource, JournalImportParseResult), Error> = await Task.detached(priority: .userInitiated) {
            Result {
                let source = try JournalImportSources.open(urls)
                return (source, try JournalImportService.parse(source, as: format))
            }
        }.value

        switch outcome {
        case .success(let (source, parsed)):
            let preview = JournalImportService.makePreview(format: format, source: source, parsed: parsed, context: viewContext)
            if preview.newDrafts.isEmpty, preview.duplicateCount == 0 {
                errorMessage = String(localized: "No entries with a date were found in that file.")
                phase = .choosing
            } else {
                phase = .preview(preview)
            }
        case .failure(let error):
            importViewLogger.error("Import read failed: \(String(describing: error), privacy: .public)")
            errorMessage = (error as? JournalImportError)?.message ?? JournalImportError.unreadable.message
            phase = .choosing
        }
    }

    private func startImport(_ preview: JournalImportPreview) {
        phase = .importing(preview, 0)
        HapticManager.shared.buttonTap()
        Task {
            do {
                let summary = try await JournalImportService.commit(preview, context: viewContext) { value in
                    phase = .importing(preview, value)
                }
                releaseScopedURLs()
                phase = .done(summary)
                HapticManager.shared.entrySaved()
            } catch {
                importViewLogger.error("Import failed: \(error.localizedDescription, privacy: .public)")
                viewContext.rollback()
                // Saved batches stay; importing again skips them.
                errorMessage = String(localized: "Couldn’t finish importing. Try again to add the rest.")
                phase = .preview(preview)
                HapticManager.shared.error()
            }
        }
    }

    private func releaseScopedURLs() {
        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
        scopedURLs = []
    }

    // MARK: - Formatting

    private static func count(_ value: Int, _ noun: String) -> String {
        switch noun {
        case "photo": return String(AttributedString(localized: "^[\(value) photo](inflect: true)").characters)
        default: return String(AttributedString(localized: "^[\(value) entry](inflect: true)").characters)
        }
    }

    private static func rangeText(_ range: ClosedRange<Date>) -> String {
        let calendar = Calendar.current
        if calendar.isDate(range.lowerBound, inSameDayAs: range.upperBound) {
            return range.lowerBound.formatted(date: .abbreviated, time: .omitted)
        }
        return (range.lowerBound..<range.upperBound).formatted(.interval.month(.abbreviated).day().year())
    }
}
