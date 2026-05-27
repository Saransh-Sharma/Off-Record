import CoreData
import Foundation
import os.log

private let weeklyReflectionControllerLogger = Logger(subsystem: "com.singularity.offrecord", category: "WeeklyReflectionController")

@MainActor
final class WeeklyReflectionController: ObservableObject {
    static let shared = WeeklyReflectionController()

    @Published private(set) var settings: WeeklyReflectionSettings
    @Published private(set) var reports: [WeeklyReflectionReport]
    @Published private(set) var currentReport: WeeklyReflectionReport?
    @Published private(set) var isPreparing = false

    private let repository: WeeklyReflectionRepository

    private init(repository: WeeklyReflectionRepository = WeeklyReflectionRepository()) {
        self.repository = repository
        let payload = repository.load()
        self.settings = payload.settings
        self.reports = payload.reports
        self.currentReport = Self.currentReport(in: payload.reports)
        WeeklyReflectionNotificationScheduler.reconcile(settings: payload.settings)
    }

    #if DEBUG
    init(repository: WeeklyReflectionRepository, scheduleNotifications: Bool = false) {
        self.repository = repository
        let payload = repository.load()
        self.settings = payload.settings
        self.reports = payload.reports
        self.currentReport = Self.currentReport(in: payload.reports)
        if scheduleNotifications {
            WeeklyReflectionNotificationScheduler.reconcile(settings: payload.settings)
        }
    }
    #endif

    func updateSettings(_ mutate: (inout WeeklyReflectionSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        persist()
        WeeklyReflectionNotificationScheduler.reconcile(settings: next)
    }

    func refreshIfNeeded(entries: [DiaryEntry], now: Date = Date(), force: Bool = false) {
        guard settings.isEnabled else {
            currentReport = nil
            return
        }
        let snapshots = entries.compactMap(WeeklyReflectionEntrySnapshot.init(entry:))
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let periodSnapshots = snapshots.filter { period.contains($0.date) }
        let hidden = currentVisibleReport(for: period)?.hiddenEntryIds ?? []
        let signature = WeeklyReflectionGenerationService.inputSignature(for: periodSnapshots.filter { !hidden.contains($0.id) }, hiddenEntryIds: hidden)

        if !force,
           let existing = currentVisibleReport(for: period),
           existing.inputSignature == signature,
           existing.status != .failed {
            currentReport = existing
            return
        }

        prepareReport(entries: snapshots, period: period, hiddenEntryIds: hidden, previousVersion: currentVisibleReport(for: period), now: now)
    }

    func openCurrentReport(entries: [DiaryEntry], now: Date = Date()) -> WeeklyReflectionReport? {
        refreshIfNeeded(entries: entries, now: now, force: false)
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        return currentVisibleReport(for: period) ?? currentReport
    }

    func report(id: UUID) -> WeeklyReflectionReport? {
        reports.first(where: { $0.id == id })
    }

    func markSeen(_ report: WeeklyReflectionReport) {
        update(reportID: report.id) { value in
            if value.status == .ready { value.status = .seen }
        }
    }

    func dismiss(_ report: WeeklyReflectionReport) {
        update(reportID: report.id) { $0.status = .dismissed }
    }

    func delete(_ report: WeeklyReflectionReport) {
        update(reportID: report.id) { $0.status = .deleted }
    }

    func saveTakeaway(_ text: String, for report: WeeklyReflectionReport) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        update(reportID: report.id) { $0.savedTakeaway = trimmed.isEmpty ? nil : trimmed }
    }

    func regenerate(report: WeeklyReflectionReport, hiding entryIds: [UUID], entries: [DiaryEntry], now: Date = Date()) {
        let snapshots = entries.compactMap(WeeklyReflectionEntrySnapshot.init(entry:))
        let hidden = Array(Set(entryIds))
        prepareReport(entries: snapshots, period: report.period, hiddenEntryIds: hidden, previousVersion: report, now: now)
    }

    var visibleReports: [WeeklyReflectionReport] {
        reports
            .filter(\.isVisibleInHistory)
            .sorted { $0.periodStart > $1.periodStart }
    }

    private func prepareReport(
        entries: [WeeklyReflectionEntrySnapshot],
        period: WeeklyReflectionPeriod,
        hiddenEntryIds: [UUID],
        previousVersion: WeeklyReflectionReport?,
        now: Date
    ) {
        isPreparing = true
        if let previousVersion {
            update(reportID: previousVersion.id, persistAfterUpdate: false) { $0.status = .superseded }
        }
        let report = WeeklyReflectionGenerationService.generate(
            period: period,
            entries: entries,
            hiddenEntryIds: hiddenEntryIds,
            previousVersion: previousVersion,
            now: now
        )
        reports.append(report)
        currentReport = report
        isPreparing = false
        persist()
        WeeklyReflectionNotificationScheduler.reconcile(settings: settings, now: now)
    }

    private func update(reportID: UUID, persistAfterUpdate: Bool = true, mutate: (inout WeeklyReflectionReport) -> Void) {
        guard let index = reports.firstIndex(where: { $0.id == reportID }) else { return }
        mutate(&reports[index])
        currentReport = Self.currentReport(in: reports)
        if persistAfterUpdate {
            persist()
        }
    }

    private func currentVisibleReport(for period: WeeklyReflectionPeriod) -> WeeklyReflectionReport? {
        reports
            .filter {
                $0.periodStart == period.start
                    && $0.periodEnd == period.end
                    && $0.isVisibleInHistory
            }
            .sorted { $0.versionNumber > $1.versionNumber }
            .first
    }

    private static func currentReport(in reports: [WeeklyReflectionReport]) -> WeeklyReflectionReport? {
        reports
            .filter(\.isVisibleInHistory)
            .sorted {
                if $0.periodStart == $1.periodStart { return $0.versionNumber > $1.versionNumber }
                return $0.periodStart > $1.periodStart
            }
            .first
    }

    private func persist() {
        do {
            try repository.save(settings: settings, reports: reports)
        } catch {
            weeklyReflectionControllerLogger.error("Failed to persist weekly reflection state: \(error.localizedDescription, privacy: .public)")
        }
    }
}
