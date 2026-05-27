import CoreData
import Foundation
import Testing
import UserNotifications
@testable import OffRecord

@MainActor
@Suite(.serialized)
struct WeeklyReflectionTests {
    @Test func weekPeriodRunsMondayThroughSundayInLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 19_800)!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 12)))

        let period = WeeklyReflectionEligibilityService.period(containing: date, calendar: calendar)
        let startComponents = WeeklyReflectionEligibilityService.calendar(from: calendar).dateComponents([.weekday, .hour, .minute], from: period.start)
        let endComponents = WeeklyReflectionEligibilityService.calendar(from: calendar).dateComponents([.weekday, .hour, .minute], from: period.end)

        #expect(startComponents.weekday == 2)
        #expect(startComponents.hour == 0)
        #expect(startComponents.minute == 0)
        #expect(endComponents.weekday == 1)
        #expect(endComponents.hour == 23)
        #expect(endComponents.minute == 59)
    }

    @Test func eligibilityBucketsFullLightAndEmpty() {
        let now = Date()
        let fullByEntries = [
            makeSnapshot(daysAgo: 0, text: mediumText, now: now),
            makeSnapshot(daysAgo: 1, text: mediumText, now: now),
            makeSnapshot(daysAgo: 2, text: mediumText, now: now)
        ]
        let light = [
            makeSnapshot(daysAgo: 0, text: mediumText, now: now),
            makeSnapshot(daysAgo: 1, text: mediumText, now: now)
        ]
        let short = [makeSnapshot(daysAgo: 0, text: "short note", now: now)]
        let fullByWords = [makeSnapshot(daysAgo: 0, text: longText, now: now)]
        let empty: [WeeklyReflectionEntrySnapshot] = []

        #expect(WeeklyReflectionEligibilityService.evaluate(entries: fullByEntries).kind == .full)
        #expect(WeeklyReflectionEligibilityService.evaluate(entries: light).kind == .light)
        #expect(WeeklyReflectionEligibilityService.evaluate(entries: short).kind == .empty)
        #expect(WeeklyReflectionEligibilityService.evaluate(entries: fullByWords).kind == .full)
        #expect(WeeklyReflectionEligibilityService.evaluate(entries: empty).kind == .empty)
    }

    @Test func repositoryPersistsReportsAndSettings() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let repository = WeeklyReflectionRepository(context: context)
        var settings = WeeklyReflectionSettings.default
        settings.showHomeCard = false
        let report = makeReport()

        try repository.save(settings: settings, reports: [report])
        let loaded = repository.load()

        #expect(loaded.settings.showHomeCard == false)
        #expect(loaded.reports.count == 1)
        #expect(loaded.reports.first?.id == report.id)
    }

    @Test func regenerationSupersedesPreviousReportAndStoresHiddenIdsOnlyOnReport() throws {
        let now = Date()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let first = makeSnapshot(daysAgo: 0, text: mediumText, now: now)
        let second = makeSnapshot(daysAgo: 1, text: mediumText, now: now)
        let initial = WeeklyReflectionGenerationService.generate(period: period, entries: [first, second], now: now)

        let regenerated = WeeklyReflectionGenerationService.generate(
            period: period,
            entries: [first, second],
            hiddenEntryIds: [first.id],
            previousVersion: initial,
            now: now.addingTimeInterval(60)
        )

        #expect(initial.versionNumber == 1)
        #expect(regenerated.versionNumber == 2)
        #expect(regenerated.hiddenEntryIds == [first.id])
        #expect(!regenerated.includedEntryIds.contains(first.id))
        #expect(regenerated.includedEntryIds.contains(second.id))
    }

    @Test func outputValidationRejectsDiagnosticLanguageAndBadEvidenceRefs() {
        var report = makeReport()
        report.summary = "You are depressed and need treatment."
        #expect(!WeeklyReflectionGenerationService.validate(report))

        report = makeReport()
        report.themes = [
            WeeklyReflectionTheme(
                id: UUID(),
                title: "Focus",
                summary: "This came up.",
                evidenceRefs: [
                    WeeklyReflectionEvidenceRef(
                        id: UUID(),
                        entryId: UUID(),
                        entryDate: Date(),
                        sourceType: .text,
                        quote: "quote",
                        reason: nil
                    )
                ]
            )
        ]
        #expect(!WeeklyReflectionGenerationService.validate(report))
    }

    @Test func weeklyNotificationRequestIsPrivacySafe() {
        let request = WeeklyReflectionNotificationScheduler.makeRequest(settings: .default, now: Date(timeIntervalSince1970: 1_800_000_000))
        let trigger = request.trigger as? UNCalendarNotificationTrigger

        #expect(request.identifier == WeeklyReflectionNotificationScheduler.identifier)
        #expect(request.content.title == "Your weekly reflection is ready")
        #expect(request.content.body == "A private look back at your week.")
        #expect(!request.content.body.lowercased().contains("anxious"))
        #expect(request.content.userInfo["offrecordRouteURL"] as? String == "offrecord://weekly-reflection/current")
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.weekday == WeeklyReflectionSettings.default.reminderWeekday)
        #expect(trigger?.dateComponents.hour == WeeklyReflectionSettings.default.reminderHour)
    }

    @Test func exportExcludesQuotesUnlessRequested() {
        var report = makeReport()
        guard let included = report.includedEntryIds.first else {
            Issue.record("Expected report to include at least one entry id.")
            return
        }
        report.themes = [
            WeeklyReflectionTheme(
                id: UUID(),
                title: "Focus",
                summary: "This came up.",
                evidenceRefs: [
                    WeeklyReflectionEvidenceRef(
                        id: UUID(),
                        entryId: included,
                        entryDate: Date(),
                        sourceType: .text,
                        quote: "I need fewer interruptions.",
                        reason: nil
                    )
                ]
            )
        ]

        let withoutQuotes = WeeklyReflectionExportService.markdown(report: report, includeQuotes: false)
        let withQuotes = WeeklyReflectionExportService.markdown(report: report, includeQuotes: true)

        #expect(!withoutQuotes.contains("I need fewer interruptions."))
        #expect(withQuotes.contains("I need fewer interruptions."))
    }

    @Test func highRiskEntriesAreExcludedFromGeneratedInsightsAndQuotes() {
        let now = Date()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let highRisk = makeSnapshot(daysAgo: 0, text: "I thought about suicide and needed care. \(longText)", now: now)
        let safe = makeSnapshot(daysAgo: 0, text: "Tea, focus, rest, and quiet planning helped me feel steadier. \(longText)", now: now)

        let report = WeeklyReflectionGenerationService.generate(period: period, entries: [highRisk, safe], now: now)
        let exported = WeeklyReflectionExportService.markdown(report: report, includeQuotes: true)
        let generatedText = ([report.heroSentence, report.summary] + report.wins + report.frictions + report.questions + report.themes.map(\.summary))
            .joined(separator: " ")
            .lowercased()

        #expect(report.safetyLevel == .highRiskExcluded)
        #expect(!generatedText.contains("suicide"))
        #expect(!exported.lowercased().contains("suicide"))
        #expect(report.themes.flatMap(\.evidenceRefs).allSatisfy { $0.entryId != highRisk.id })
        #expect(WeeklyReflectionGenerationService.validate(report, highRiskEntryIds: [highRisk.id]))
    }

    @Test func allHighRiskInputProducesSupportOnlyReportWithoutEvidenceRefs() {
        let now = Date()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let highRisk = makeSnapshot(daysAgo: 0, text: "I thought about suicide and needed care. \(longText)", now: now)

        let report = WeeklyReflectionGenerationService.generate(period: period, entries: [highRisk], now: now)

        #expect(report.safetyLevel == .highRiskExcluded)
        #expect(report.themes.isEmpty)
        #expect(report.themes.flatMap(\.evidenceRefs).isEmpty)
        #expect(report.includedEntryIds.contains(highRisk.id))
        #expect(!WeeklyReflectionExportService.markdown(report: report, includeQuotes: true).lowercased().contains("suicide"))
    }

    @Test func dismissedReportHidesFromHomeButStaysInHistoryAndDeleteRemovesFromHistory() {
        var dismissed = makeReport()
        dismissed.status = .dismissed
        var deleted = makeReport()
        deleted.status = .deleted

        #expect(!dismissed.isVisibleOnHome)
        #expect(dismissed.isVisibleInHistory)
        #expect(!deleted.isVisibleOnHome)
        #expect(!deleted.isVisibleInHistory)
    }

    @Test func currentOpenDoesNotRegenerateWhenSignatureIsUnchanged() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let repository = WeeklyReflectionRepository(context: context)
        var settings = WeeklyReflectionSettings.default
        settings.sendNotification = false
        try repository.save(settings: settings, reports: [])
        let controller = WeeklyReflectionController(repository: repository)
        let entries = [
            makeEntry(context: context, text: mediumText),
            makeEntry(context: context, text: mediumText),
            makeEntry(context: context, text: mediumText)
        ]
        try context.save()

        let first = try #require(controller.openCurrentReport(entries: entries))
        let second = try #require(controller.openCurrentReport(entries: entries))

        #expect(first.id == second.id)
        #expect(controller.reports.filter { $0.periodStart == first.periodStart }.count == 1)
    }

    @Test func currentOpenRegeneratesWhenSignatureIsStale() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let repository = WeeklyReflectionRepository(context: context)
        var settings = WeeklyReflectionSettings.default
        settings.sendNotification = false
        try repository.save(settings: settings, reports: [])
        let controller = WeeklyReflectionController(repository: repository)
        let entry = makeEntry(context: context, text: longText)
        try context.save()
        let first = try #require(controller.openCurrentReport(entries: [entry]))

        entry.text = "\(longText) updated focus"
        entry.updatedAt = Date().addingTimeInterval(60)
        try context.save()
        let second = try #require(controller.openCurrentReport(entries: [entry]))

        #expect(first.id != second.id)
        #expect(second.versionNumber == first.versionNumber + 1)
        #expect(controller.report(id: first.id)?.status == .superseded)
    }

    @Test func hiddenSourcesCanBeReincludedOnNextVersion() {
        let now = Date()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let first = makeSnapshot(daysAgo: 0, text: mediumText, now: now)
        let second = makeSnapshot(daysAgo: 0, text: mediumText, now: now)
        let hidden = WeeklyReflectionGenerationService.generate(
            period: period,
            entries: [first, second],
            hiddenEntryIds: [first.id],
            now: now
        )
        let reincluded = WeeklyReflectionGenerationService.generate(
            period: period,
            entries: [first, second],
            hiddenEntryIds: [],
            previousVersion: hidden,
            now: now.addingTimeInterval(60)
        )

        #expect(!hidden.includedEntryIds.contains(first.id))
        #expect(reincluded.includedEntryIds.contains(first.id))
        #expect(reincluded.hiddenEntryIds.isEmpty)
    }

    private func makeSnapshot(daysAgo: Int, text: String, now: Date) -> WeeklyReflectionEntrySnapshot {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return WeeklyReflectionEntrySnapshot(
            id: UUID(),
            date: date,
            updatedAt: date,
            mood: Mood.calm.rawValue,
            text: text,
            sourceType: .text
        )
    }

    private var mediumText: String {
        String(repeating: "focus rest boundary quiet planning ", count: 30)
    }

    private var longText: String {
        String(repeating: "focus rest boundary quiet planning ", count: 125)
    }

    private func makeEntry(context: NSManagedObjectContext, text: String) -> DiaryEntry {
        let now = Date()
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now
        entry.text = text
        entry.mood = Mood.calm.rawValue
        entry.duration = 0
        return entry
    }

    private func makeReport() -> WeeklyReflectionReport {
        let entryID = UUID()
        let now = Date()
        return WeeklyReflectionReport(
            id: UUID(),
            periodStart: now.addingTimeInterval(-6 * 24 * 60 * 60),
            periodEnd: now,
            generatedAt: now,
            versionNumber: 1,
            processingMode: .local,
            status: .ready,
            eligibility: .full,
            includedEntryIds: [entryID],
            hiddenEntryIds: [],
            unavailableEntryIds: [],
            privateEntryCount: 0,
            inputSignature: "test",
            heroSentence: "This week had a thread worth naming.",
            summary: "Your entries suggest work and rest shaped the week.",
            emotionalArc: WeeklyReflectionEmotionalArc(label: "Steady", description: "The tone stayed steady."),
            themes: [
                WeeklyReflectionTheme(
                    id: UUID(),
                    title: "Focus",
                    summary: "This came up in one entry.",
                    evidenceRefs: [
                        WeeklyReflectionEvidenceRef(
                            id: UUID(),
                            entryId: entryID,
                            entryDate: now,
                            sourceType: .text,
                            quote: "I need fewer interruptions.",
                            reason: nil
                        )
                    ]
                )
            ],
            wins: ["You made space to write."],
            frictions: ["Heavier language appeared briefly."],
            questions: ["What would make next week lighter?"],
            savedTakeaway: nil,
            safetyLevel: .none,
            userMarkedHelpful: nil
        )
    }
}
