import CoreData
import Foundation
import NaturalLanguage
import os.log
import UserNotifications

private let weeklyReflectionLogger = Logger(subsystem: "com.singularity.offrecord", category: "WeeklyReflection")

enum WeeklyReflectionEligibilityService {
    static func calendar(from base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func period(containing date: Date = Date(), calendar baseCalendar: Calendar = .current) -> WeeklyReflectionPeriod {
        let calendar = calendar(from: baseCalendar)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? date
        return WeeklyReflectionPeriod(start: start, end: end)
    }

    static func evaluate(entries: [WeeklyReflectionEntrySnapshot]) -> WeeklyReflectionEligibility {
        let entryCount = entries.count
        let wordCount = entries.reduce(0) { $0 + $1.wordCount }
        let kind: WeeklyReflectionEligibilityKind
        if entryCount == 0 || wordCount < 150 {
            kind = .empty
        } else if entryCount >= 3 || wordCount >= 600 {
            kind = .full
        } else {
            kind = .light
        }
        return WeeklyReflectionEligibility(kind: kind, entryCount: entryCount, wordCount: wordCount)
    }
}

enum WeeklyReflectionSafetyFilter {
    private static let highRiskTerms = [
        "kill myself", "suicide", "end my life", "self harm", "self-harm", "hurt myself"
    ]

    private static let forbiddenOutputTerms = [
        "you are depressed", "you have depression", "you are anxious", "you have anxiety",
        "burnout diagnosis", "treatment plan", "stop taking medication",
        "you are burned out", "you have burnout"
    ]

    static func isHighRisk(_ entry: WeeklyReflectionEntrySnapshot) -> Bool {
        let text = entry.text.lowercased()
        return highRiskTerms.contains(where: text.contains)
    }

    static func safetyLevel(for entries: [WeeklyReflectionEntrySnapshot]) -> WeeklyReflectionSafetyLevel {
        if entries.contains(where: isHighRisk) {
            return .highRiskExcluded
        }
        let joined = entries.map(\.text).joined(separator: " ").lowercased()
        if joined.contains("overwhelmed") || joined.contains("exhausted") || joined.contains("panic") {
            return .mildDistress
        }
        return .none
    }

    static func sanitized(_ text: String) -> String {
        var value = text
        for term in forbiddenOutputTerms {
            value = value.replacingOccurrences(of: term, with: "your entries suggest a heavier moment", options: [.caseInsensitive])
        }
        value = value.replacingOccurrences(of: "You are ", with: "Your entries suggest ", options: [.caseInsensitive])
        value = value.replacingOccurrences(of: "You need to ", with: "A question to consider is whether to ", options: [.caseInsensitive])
        return value
    }

    static func isValidOutput(_ report: WeeklyReflectionReport) -> Bool {
        let text = ([report.heroSentence, report.summary] + report.wins + report.frictions + report.questions + report.themes.map(\.summary))
            .joined(separator: " ")
            .lowercased()
        return !forbiddenOutputTerms.contains(where: text.contains)
    }
}

enum WeeklyReflectionGenerationService {
    static func generate(
        period: WeeklyReflectionPeriod,
        entries allEntries: [WeeklyReflectionEntrySnapshot],
        hiddenEntryIds: [UUID] = [],
        previousVersion: WeeklyReflectionReport? = nil,
        now: Date = Date()
    ) -> WeeklyReflectionReport {
        let hiddenSet = Set(hiddenEntryIds)
        let periodEntries = allEntries
            .filter { period.contains($0.date) && !hiddenSet.contains($0.id) }
            .sorted { $0.date < $1.date }
        let eligibility = WeeklyReflectionEligibilityService.evaluate(entries: periodEntries)
        let highRiskIDs = Set(periodEntries.filter(WeeklyReflectionSafetyFilter.isHighRisk).map(\.id))
        let insightEntries = periodEntries.filter { !highRiskIDs.contains($0.id) }
        let unavailable = previousVersion?.includedEntryIds.filter { id in
            !allEntries.contains(where: { $0.id == id })
        } ?? []

        if eligibility.kind == .empty {
            return baseReport(
                period: period,
                eligibility: .empty,
                status: .insufficientData,
                entries: periodEntries,
                hiddenEntryIds: hiddenEntryIds,
                unavailableEntryIds: unavailable,
                previousVersion: previousVersion,
                now: now,
                heroSentence: "No weekly reflection yet.",
                summary: "Add a few thoughts this week and OffRecord will help you look back privately.",
                emotionalArc: nil,
                themes: [],
                wins: [],
                frictions: [],
                questions: ["What is one small moment worth writing down this week?"],
                safetyLevel: .none
            )
        }

        let safetyLevel = WeeklyReflectionSafetyFilter.safetyLevel(for: periodEntries)
        if safetyLevel == .highRiskExcluded, insightEntries.isEmpty {
            return baseReport(
                period: period,
                eligibility: eligibility.kind,
                status: .ready,
                entries: periodEntries,
                hiddenEntryIds: hiddenEntryIds,
                unavailableEntryIds: unavailable,
                previousVersion: previousVersion,
                now: now,
                heroSentence: "This week seemed to ask for extra care.",
                summary: "Some entries this week seemed heavier than usual, so this reflection stays gentle and avoids quoting or interpreting those moments. You can still review the sources privately.",
                emotionalArc: nil,
                themes: [],
                wins: ["You made space to write, even when the week felt heavy."],
                frictions: ["Some entries seemed heavier than usual, so OffRecord keeps them out of generated insights."],
                questions: ["What kind of support would feel safe to reach for this week?", "What is one small next step that asks less of you?"],
                safetyLevel: safetyLevel
            )
        }

        let topics = topTopics(in: insightEntries, limit: eligibility.kind == .full ? 4 : 2)
        let themes = makeThemes(topics: topics, entries: insightEntries, limit: eligibility.kind == .full ? 4 : 2)
        let arc = makeEmotionalArc(entries: insightEntries)
        let entryDays = Set(periodEntries.map { Calendar.current.startOfDay(for: $0.date) }).count
        let hero = heroSentence(for: eligibility.kind, topics: topics, arc: arc, safetyLevel: safetyLevel)
        let summary = summaryText(entries: periodEntries, topics: topics, arc: arc, eligibility: eligibility, safetyLevel: safetyLevel)

        var wins = [
            "You made space to write on \(entryDays) \(entryDays == 1 ? "day" : "different days").",
            "You left enough context to notice what kept returning."
        ]
        if insightEntries.contains(where: { $0.sentiment > 0.25 }) {
            wins.append("Some entries carried lighter or more appreciative language.")
        }
        wins = Array(wins.prefix(eligibility.kind == .full ? 3 : 1))

        var frictions: [String] = []
        if safetyLevel == .highRiskExcluded {
            frictions.append("Some entries seemed heavier than usual, so OffRecord keeps this reflection careful and separate from support.")
        } else if insightEntries.contains(where: { $0.sentiment < -0.2 }) {
            frictions.append("Heavier language appeared in parts of the week.")
        }
        if let firstTopic = topics.first {
            frictions.append("\(firstTopic.capitalized) came up more than once, which may be worth noticing gently.")
        }
        if frictions.isEmpty {
            frictions.append("The week had limited friction signals, so this recap avoids over-reading it.")
        }
        frictions = Array(frictions.prefix(eligibility.kind == .full ? 3 : 1))

        let questions = makeQuestions(topics: topics, eligibility: eligibility.kind)

        return baseReport(
            period: period,
            eligibility: eligibility.kind,
            status: .ready,
            entries: periodEntries,
            hiddenEntryIds: hiddenEntryIds,
            unavailableEntryIds: unavailable,
            previousVersion: previousVersion,
            now: now,
            heroSentence: hero,
            summary: summary,
            emotionalArc: arc,
            themes: themes,
            wins: wins,
            frictions: frictions,
            questions: questions,
            safetyLevel: safetyLevel
        )
    }

    static func validate(_ report: WeeklyReflectionReport) -> Bool {
        guard report.heroSentence.split(separator: " ").count <= 25 else { return false }
        guard report.summary.split(separator: " ").count <= 120 else { return false }
        guard report.questions.count >= 1 && report.questions.count <= 3 else { return false }
        guard report.wins.count <= 3 && report.frictions.count <= 3 else { return false }
        let included = Set(report.includedEntryIds)
        let refs = report.themes.flatMap(\.evidenceRefs)
        guard refs.allSatisfy({ included.contains($0.entryId) }) else { return false }
        return WeeklyReflectionSafetyFilter.isValidOutput(report)
    }

    static func validate(_ report: WeeklyReflectionReport, highRiskEntryIds: Set<UUID>) -> Bool {
        guard validate(report) else { return false }
        let refs = report.themes.flatMap(\.evidenceRefs)
        return refs.allSatisfy { !highRiskEntryIds.contains($0.entryId) }
    }

    private static func baseReport(
        period: WeeklyReflectionPeriod,
        eligibility: WeeklyReflectionEligibilityKind,
        status: WeeklyReflectionStatus,
        entries: [WeeklyReflectionEntrySnapshot],
        hiddenEntryIds: [UUID],
        unavailableEntryIds: [UUID],
        previousVersion: WeeklyReflectionReport?,
        now: Date,
        heroSentence: String,
        summary: String,
        emotionalArc: WeeklyReflectionEmotionalArc?,
        themes: [WeeklyReflectionTheme],
        wins: [String],
        frictions: [String],
        questions: [String],
        safetyLevel: WeeklyReflectionSafetyLevel
    ) -> WeeklyReflectionReport {
        let report = WeeklyReflectionReport(
            id: UUID(),
            periodStart: period.start,
            periodEnd: period.end,
            generatedAt: now,
            versionNumber: (previousVersion?.versionNumber ?? 0) + 1,
            processingMode: .local,
            status: status,
            eligibility: eligibility,
            includedEntryIds: entries.map(\.id),
            hiddenEntryIds: hiddenEntryIds,
            unavailableEntryIds: unavailableEntryIds,
            privateEntryCount: 0,
            inputSignature: inputSignature(for: entries, hiddenEntryIds: hiddenEntryIds),
            heroSentence: WeeklyReflectionSafetyFilter.sanitized(heroSentence),
            summary: WeeklyReflectionSafetyFilter.sanitized(summary),
            emotionalArc: emotionalArc,
            themes: themes,
            wins: wins.map(WeeklyReflectionSafetyFilter.sanitized),
            frictions: frictions.map(WeeklyReflectionSafetyFilter.sanitized),
            questions: questions.map(WeeklyReflectionSafetyFilter.sanitized),
            savedTakeaway: previousVersion?.savedTakeaway,
            safetyLevel: safetyLevel,
            userMarkedHelpful: previousVersion?.userMarkedHelpful
        )
        return validate(report) ? report : failedReport(period: period, previousVersion: previousVersion, now: now)
    }

    private static func failedReport(period: WeeklyReflectionPeriod, previousVersion: WeeklyReflectionReport?, now: Date) -> WeeklyReflectionReport {
        WeeklyReflectionReport(
            id: UUID(),
            periodStart: period.start,
            periodEnd: period.end,
            generatedAt: now,
            versionNumber: (previousVersion?.versionNumber ?? 0) + 1,
            processingMode: .local,
            status: .failed,
            eligibility: .empty,
            includedEntryIds: [],
            hiddenEntryIds: previousVersion?.hiddenEntryIds ?? [],
            unavailableEntryIds: [],
            privateEntryCount: 0,
            inputSignature: "failed-\(now.timeIntervalSince1970)",
            heroSentence: "Reflection could not be created.",
            summary: "Your entries are safe. OffRecord could not prepare this reflection right now.",
            emotionalArc: nil,
            themes: [],
            wins: [],
            frictions: [],
            questions: ["Would you like to try again?"],
            savedTakeaway: previousVersion?.savedTakeaway,
            safetyLevel: .none,
            userMarkedHelpful: previousVersion?.userMarkedHelpful
        )
    }

    static func inputSignature(for entries: [WeeklyReflectionEntrySnapshot], hiddenEntryIds: [UUID] = []) -> String {
        let entryPart = entries
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.wordCount)" }
            .joined(separator: "|")
        let hiddenPart = hiddenEntryIds.map(\.uuidString).sorted().joined(separator: "|")
        return "\(entryPart)#hidden:\(hiddenPart)"
    }

    private static func heroSentence(
        for kind: WeeklyReflectionEligibilityKind,
        topics: [String],
        arc: WeeklyReflectionEmotionalArc?,
        safetyLevel: WeeklyReflectionSafetyLevel
    ) -> String {
        if safetyLevel == .highRiskExcluded {
            return "This week seemed to ask for extra care."
        }
        if kind == .light {
            return "A small reflection is ready from what you wrote."
        }
        if let first = topics.first, let arc {
            return "This week brought \(first) into focus, with an arc of \(arc.label.lowercased())."
        }
        return "This week left a few threads worth naming."
    }

    private static func summaryText(
        entries: [WeeklyReflectionEntrySnapshot],
        topics: [String],
        arc: WeeklyReflectionEmotionalArc?,
        eligibility: WeeklyReflectionEligibility,
        safetyLevel: WeeklyReflectionSafetyLevel
    ) -> String {
        let topicText = topics.isEmpty ? "a few personal threads" : topics.prefix(3).joined(separator: ", ")
        var parts = [
            "Your entries suggest that \(topicText) shaped the week.",
            "You wrote \(eligibility.entryCount) \(eligibility.entryCount == 1 ? "entry" : "entries") with about \(eligibility.wordCount) words."
        ]
        if let arc {
            parts.append(arc.description)
        }
        if safetyLevel == .highRiskExcluded {
            parts.append("Because some language seemed heavier than usual, this recap stays careful and avoids turning support into advice.")
        } else {
            parts.append("This is a reflection from your words, not a diagnosis or medical advice.")
        }
        return parts.joined(separator: " ")
    }

    private static func makeEmotionalArc(entries: [WeeklyReflectionEntrySnapshot]) -> WeeklyReflectionEmotionalArc? {
        guard entries.count >= 2 else { return nil }
        let first = entries.prefix(max(1, entries.count / 2)).map(\.sentiment).reduce(0, +) / Double(max(1, entries.count / 2))
        let secondItems = entries.suffix(max(1, entries.count - entries.count / 2))
        let second = secondItems.map(\.sentiment).reduce(0, +) / Double(max(1, secondItems.count))
        let label: String
        let description: String
        if second > first + 0.15 {
            label = "Heavier to lighter"
            description = "Your entries moved toward lighter language near the end of the week."
        } else if second < first - 0.15 {
            label = "Lighter to heavier"
            description = "Your entries began lighter and ended with more fatigue or friction."
        } else {
            label = "Steady"
            description = "The emotional tone stayed fairly steady across the week."
        }
        return WeeklyReflectionEmotionalArc(label: label, description: description)
    }

    private static func makeThemes(topics: [String], entries: [WeeklyReflectionEntrySnapshot], limit: Int) -> [WeeklyReflectionTheme] {
        let selected = topics.isEmpty ? ["Writing rhythm"] : Array(topics.prefix(limit))
        return selected.map { topic in
            let matches = entries.filter { $0.text.localizedCaseInsensitiveContains(topic) }
            let evidenceEntries = (matches.isEmpty ? entries : matches).prefix(3)
            let refs = evidenceEntries.map { entry in
                WeeklyReflectionEvidenceRef(
                    id: UUID(),
                    entryId: entry.id,
                    entryDate: entry.date,
                    sourceType: entry.sourceType,
                    quote: ProactiveReflectionAnalyzer.snippet(entry.text),
                    reason: "This entry helped support the theme."
                )
            }
            return WeeklyReflectionTheme(
                id: UUID(),
                title: topic.capitalized,
                summary: "This came up in \(refs.count) \(refs.count == 1 ? "entry" : "entries") and may be worth revisiting gently.",
                evidenceRefs: refs
            )
        }
    }

    private static func makeQuestions(topics: [String], eligibility: WeeklyReflectionEligibilityKind) -> [String] {
        var questions = [
            "What would make next week feel 10% lighter?",
            "Where did you feel most like yourself this week?"
        ]
        if let topic = topics.first {
            questions.insert("What do you want to carry forward about \(topic)?", at: 0)
        }
        return Array(questions.prefix(eligibility == .full ? 3 : 2))
    }

    private static func topTopics(in entries: [WeeklyReflectionEntrySnapshot], limit: Int) -> [String] {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "and", "because", "been", "but", "could", "from",
            "have", "into", "just", "like", "more", "much", "that", "the", "this", "was", "were",
            "with", "would", "your", "their", "there", "today", "week", "really", "felt", "feel"
        ]
        var counts: [String: Int] = [:]
        let tokenizer = NLTokenizer(unit: .word)
        for entry in entries {
            let text = entry.text.lowercased()
            tokenizer.string = text
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let token = String(text[range])
                    .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard token.count >= 4, !stopWords.contains(token), token.rangeOfCharacter(from: .decimalDigits) == nil else {
                    return true
                }
                counts[token, default: 0] += 1
                return true
            }
        }
        return counts.sorted {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }
        .prefix(limit)
        .map(\.key)
    }
}

struct WeeklyReflectionRepository {
    private let stateType = "weekly_reflection_reports"
    let context: NSManagedObjectContext

    struct Payload: Codable {
        var version: Int
        var settings: WeeklyReflectionSettings
        var reports: [WeeklyReflectionReport]
    }

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    func load() -> Payload {
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", stateType)
        request.fetchLimit = 1
        guard let state = try? context.fetch(request).first,
              let data = state.payload,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1 else {
            return Payload(version: 1, settings: .default, reports: [])
        }
        return payload
    }

    func save(settings: WeeklyReflectionSettings, reports: [WeeklyReflectionReport]) throws {
        let payload = Payload(version: 1, settings: settings, reports: reports)
        let data = try JSONEncoder().encode(payload)
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", stateType)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first
        let state = existing ?? AIState(context: context)
        if existing == nil {
            state.id = UUID()
            state.type = stateType
        }
        state.payload = data
        state.updatedAt = Date()
        try context.save()
    }
}

enum WeeklyReflectionNotificationScheduler {
    static let identifier = "offrecord_weekly_reflection_ready"

    static func makeRequest(settings: WeeklyReflectionSettings, now: Date = Date(), calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Your weekly reflection is ready"
        content.body = "A private look back at your week."
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_REFLECTION_READY"
        if let url = OffRecordNavigationRouter.url(for: .weeklyReflectionCurrent) {
            content.userInfo = ["offrecordRouteURL": url.absoluteString]
        }

        var components = DateComponents()
        components.weekday = settings.reminderWeekday
        components.hour = settings.reminderHour
        components.minute = settings.reminderMinute
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
    }

    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                weeklyReflectionLogger.error("Failed to request weekly reflection notification permission: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    static func reconcile(settings: WeeklyReflectionSettings, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard settings.isEnabled, settings.sendNotification else { return }
        center.add(makeRequest(settings: settings, now: now)) { error in
            if let error {
                weeklyReflectionLogger.error("Failed to schedule weekly reflection notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum WeeklyReflectionExportService {
    enum Format: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        case plainText = "Plain Text"

        var id: String { rawValue }
    }

    static func export(report: WeeklyReflectionReport, format: Format, includeQuotes: Bool) throws -> URL {
        let text = format == .markdown
            ? markdown(report: report, includeQuotes: includeQuotes)
            : plainText(report: report, includeQuotes: includeQuotes)
        let fileName = "OffRecord-Weekly-Reflection-\(Int(report.generatedAt.timeIntervalSince1970)).\(format == .markdown ? "md" : "txt")"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func markdown(report: WeeklyReflectionReport, includeQuotes: Bool) -> String {
        var lines: [String] = [
            "# Your Week in Review",
            "",
            "\(dateRange(report))",
            "",
            "> \(report.heroSentence)",
            "",
            "## Summary",
            report.summary,
            ""
        ]
        appendSections(to: &lines, report: report, includeQuotes: includeQuotes, markdown: true)
        return lines.joined(separator: "\n")
    }

    static func plainText(report: WeeklyReflectionReport, includeQuotes: Bool) -> String {
        var lines: [String] = [
            "Your Week in Review",
            dateRange(report),
            "",
            report.heroSentence,
            "",
            "Summary",
            report.summary,
            ""
        ]
        appendSections(to: &lines, report: report, includeQuotes: includeQuotes, markdown: false)
        return lines.joined(separator: "\n")
    }

    private static func appendSections(to lines: inout [String], report: WeeklyReflectionReport, includeQuotes: Bool, markdown: Bool) {
        let header = { (text: String) -> String in markdown ? "## \(text)" : text }
        if let arc = report.emotionalArc {
            lines += [header("Emotional Arc"), "\(arc.label): \(arc.description)", ""]
        }
        if !report.themes.isEmpty {
            lines.append(header("Themes"))
            for theme in report.themes {
                lines.append(markdown ? "- **\(theme.title):** \(theme.summary)" : "- \(theme.title): \(theme.summary)")
                if includeQuotes {
                    for ref in theme.evidenceRefs where ref.quote?.isEmpty == false {
                        lines.append(markdown ? "  - \"\(ref.quote ?? "")\"" : "  - \"\(ref.quote ?? "")\"")
                    }
                }
            }
            lines.append("")
        }
        if !report.wins.isEmpty {
            lines += [header("Small Wins")]
            lines += report.wins.map { "- \($0)" }
            lines.append("")
        }
        if !report.frictions.isEmpty {
            lines += [header("What Felt Heavy")]
            lines += report.frictions.map { "- \($0)" }
            lines.append("")
        }
        if !report.questions.isEmpty {
            lines += [header("Questions for Next Week")]
            lines += report.questions.map { "- \($0)" }
            lines.append("")
        }
        lines += [
            "Generated on-device by OffRecord.",
            "This is a reflection from your journal, not a diagnosis or medical advice."
        ]
    }

    private static func dateRange(_ report: WeeklyReflectionReport) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: report.periodStart)) - \(formatter.string(from: report.periodEnd))"
    }
}
