import Foundation
import Testing
@testable import OffRecord

/// Session Prep: the deterministic summary, quote choices (none by default), and name replacement.
struct SessionPrepTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, hour: Int = 20) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private var range: (Date, Date) {
        (calendar.startOfDay(for: day(0)), calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: day(27)))!)
    }

    private func entry(_ offset: Int, _ text: String, mood: Mood = .calm, analysisText: String? = nil) -> SessionPrepEntry {
        SessionPrepEntry(
            id: UUID(),
            date: day(offset),
            analysisText: analysisText ?? text,
            quoteText: text,
            mood: mood,
            wordCount: text.split(whereSeparator: \.isWhitespace).count
        )
    }

    private var entries: [SessionPrepEntry] {
        [
            entry(0, "Work was heavy today. The project review with my manager went badly.", mood: .anxious),
            entry(3, "Couldn't sleep after work again. Thinking about the project all night.", mood: .tired),
            entry(16, "Started running in the mornings with Maya. Running clears my head before work.", mood: .calm),
            entry(18, "Running again with Maya. The project feels smaller this week.", mood: .happy),
            entry(20, "A good day at work and a long run with Maya after.", mood: .happy),
            entry(24, "Running is now a habit. Dinner with Maya and her brother.", mood: .grateful)
        ]
    }

    @Test func summaryCountsMoodsThemesAndChanges() {
        let (start, end) = range
        let summary = SessionPrepBuilder.summary(for: entries, start: start, end: end, calendar: calendar)

        #expect(summary.entryCount == 6)
        #expect(summary.activeDays == 6)
        #expect(summary.daysWithMood == 6)
        #expect(summary.moodDirection == 1)
        #expect(summary.notableChanges.contains("Moods were lighter in the second half."))
        #expect(summary.themes.contains { $0.title.lowercased() == "project" || $0.title.lowercased() == "work" })
        #expect(summary.excludedEntryCount == 0)
        // Deterministic: same input, same output.
        #expect(summary == SessionPrepBuilder.summary(for: entries, start: start, end: end, calendar: calendar))
    }

    @Test func writingMoreOftenLaterIsANotableChange() {
        let (start, end) = range
        let late = [entry(1, "One early note about the week ahead and the plans for it.")]
            + (14...19).map { entry($0, "Later note number \($0) about the garden and the weather this week.") }
        let summary = SessionPrepBuilder.summary(for: late, start: start, end: end, calendar: calendar)

        #expect(summary.notableChanges.first == "Wrote more often in the second half: 6 entries, up from 1.")
    }

    @Test func quotesAreOffByDefault() {
        let (start, end) = range
        let options = SessionPrepOptions(start: start, end: end)
        #expect(options.selectedQuoteIDs.isEmpty)

        let document = SessionPrepBuilder.document(entries: entries, options: options, calendar: calendar)
        #expect(!document.sections.contains { $0.style == .quotes })
        let markdown = SessionPrepBuilder.markdown(document)
        for entry in entries {
            #expect(!markdown.contains(entry.quoteText))
        }
    }

    @Test func pickedQuotesAppearInDateOrder() {
        let (start, end) = range
        let picked = [entries[4], entries[1]]
        var options = SessionPrepOptions(start: start, end: end)
        options.selectedQuoteIDs = Set(picked.map(\.id))
        options.replaceNames = false

        let document = SessionPrepBuilder.document(entries: entries, options: options, calendar: calendar)
        let quotes = document.sections.first { $0.style == .quotes }?.items ?? []

        #expect(quotes.count == 2)
        #expect(quotes[0].contains("Couldn't sleep"))
        #expect(quotes[1].contains("A good day at work"))
    }

    @Test func highRiskEntriesStayOutOfTheSummaryButCanBeQuotedByChoice() {
        let (start, end) = range
        let risky = entry(10, "I keep thinking about suicide when the project goes wrong at work.", mood: .sad)
        var all = entries
        all.append(risky)

        let summary = SessionPrepBuilder.summary(for: all, start: start, end: end, calendar: calendar)
        #expect(summary.excludedEntryCount == 1)
        #expect(summary.entryCount == 7)

        let unpicked = SessionPrepBuilder.document(entries: all, options: SessionPrepOptions(start: start, end: end), calendar: calendar)
        let unpickedText = SessionPrepBuilder.plainText(unpicked)
        #expect(!unpickedText.contains("suicide"))
        #expect(unpickedText.contains("left out of the summary"))

        var options = SessionPrepOptions(start: start, end: end)
        options.selectedQuoteIDs = [risky.id]
        let picked = SessionPrepBuilder.document(entries: all, options: options, calendar: calendar)
        #expect(SessionPrepBuilder.plainText(picked).contains("suicide"))
        #expect(SessionPrepBuilder.quoteCandidates(all).contains { $0.id == risky.id })
    }

    @Test func entriesExcludedFromAIAreCountedNotRead() {
        let (start, end) = range
        let hidden = entry(12, "Private project notes about the move and the new apartment search.", analysisText: "")
        let summary = SessionPrepBuilder.summary(for: entries + [hidden], start: start, end: end, calendar: calendar)

        #expect(summary.entryCount == 7)
        #expect(!summary.themes.contains { $0.title.lowercased() == "apartment" })
    }

    @Test func namesAreReplacedEverywhereWhenChosen() {
        let (start, end) = range
        var options = SessionPrepOptions(start: start, end: end)
        options.selectedQuoteIDs = Set(entries.map(\.id))
        options.bringUp = "How things are going with Maya."
        options.replaceNames = true

        let document = SessionPrepBuilder.document(entries: entries, options: options, knownNames: ["Maya"], calendar: calendar)
        let markdown = SessionPrepBuilder.markdown(document)
        let text = SessionPrepBuilder.plainText(document)

        #expect(!markdown.contains("Maya"))
        #expect(!text.contains("Maya"))
        #expect(markdown.contains(ShareableInsightPrivacy.placeholder))
        #expect(document.footnotes.contains { $0.contains("someone") })

        options.replaceNames = false
        let named = SessionPrepBuilder.markdown(SessionPrepBuilder.document(entries: entries, options: options, knownNames: ["Maya"], calendar: calendar))
        #expect(named.contains("Maya"))
    }

    @Test func bringUpTextAndFormatsAreIncluded() {
        let (start, end) = range
        var options = SessionPrepOptions(start: start, end: end)
        options.bringUp = "Sleep, and the project deadline."
        options.replaceNames = false
        let document = SessionPrepBuilder.document(entries: entries, options: options, deviceNoun: "iPad", calendar: calendar)

        let markdown = SessionPrepBuilder.markdown(document)
        #expect(markdown.hasPrefix("# Session Prep"))
        #expect(markdown.contains("## What I Want to Bring Up\nSleep, and the project deadline."))
        #expect(markdown.contains("on your iPad"))
        #expect(!markdown.lowercased().contains("therapy"))

        let plain = SessionPrepBuilder.plainText(document)
        #expect(plain.contains("Sleep, and the project deadline."))
        #expect(!plain.contains("##"))
    }

    @Test func excerptsStopAtASentence() {
        let long = String(repeating: "This is a sentence about the day. ", count: 30)
        let excerpt = SessionPrepBuilder.excerpt(long)
        #expect(excerpt.count <= SessionPrepBuilder.excerptLength)
        #expect(excerpt.hasSuffix("."))
        #expect(SessionPrepBuilder.excerpt("Short one.") == "Short one.")
    }

    @MainActor
    @Test func pdfAndTextFilesAreWritten() throws {
        let (start, end) = range
        var options = SessionPrepOptions(start: start, end: end)
        options.selectedQuoteIDs = Set(entries.prefix(2).map(\.id))
        let document = SessionPrepBuilder.document(entries: entries, options: options, calendar: calendar)

        let pdf = try SessionPrepExport.write(document, format: .pdf, start: start, end: end)
        let pdfData = try Data(contentsOf: pdf)
        #expect(pdfData.starts(with: Array("%PDF".utf8)))
        #expect(pdf.lastPathComponent == "OffRecord-Session-Prep-2026-09-01-to-2026-09-28.pdf")

        let markdown = try SessionPrepExport.write(document, format: .markdown, start: start, end: end)
        #expect(try String(contentsOf: markdown, encoding: .utf8).hasPrefix("# Session Prep"))
        let plain = try SessionPrepExport.write(document, format: .plainText, start: start, end: end)
        #expect(plain.pathExtension == "txt")
    }
}
