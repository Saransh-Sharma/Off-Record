import Foundation
import Testing
import JournalFoundation
@testable import ReflectionKit

/// Weekly snapshots honor `JournalAIExclusion`: kept-out entries count but
/// carry no text, and entries left out of reflection don't count at all.
struct ReflectionExclusionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(words: Int, mood: String? = nil, exclusion: JournalAIExclusion = .included) -> WeeklyReflectionEntrySnapshot {
        WeeklyReflectionEntrySnapshot(
            id: UUID(),
            date: start.addingTimeInterval(3_600),
            updatedAt: start,
            mood: mood,
            text: Array(repeating: "private", count: words).joined(separator: " "),
            sourceType: .text,
            aiExclusion: exclusion
        )
    }

    @Test func defaultSnapshotIsIncludedAndKeepsText() {
        let included = WeeklyReflectionEntrySnapshot(
            id: UUID(), date: start, updatedAt: start, mood: nil, text: "  Walk by the lake.  ", sourceType: .text
        )
        #expect(included.aiExclusion == .included)
        #expect(included.text == "Walk by the lake.")
        #expect(included.wordCount == 4)
    }

    @Test func keptOutSnapshotCountsWordsWithoutText() {
        let keptOut = snapshot(words: 160, mood: "sad", exclusion: .excludedFromAI)
        #expect(keptOut.text.isEmpty)
        #expect(keptOut.wordCount == 160)
        #expect(keptOut.sentiment == ReflectionSentiment.score(text: "", mood: "sad"))
    }

    @Test func eligibilityCountsKeptOutButNotLeftOutEntries() {
        let period = WeeklyReflectionPeriod(start: start, end: start.addingTimeInterval(7 * 24 * 60 * 60))

        let keptOut = WeeklyReflectionEligibilityEngine.evaluate(entries: [snapshot(words: 160, exclusion: .excludedFromAI)], in: period)
        #expect(keptOut.kind == .light)
        #expect(keptOut.entryCount == 1)
        #expect(keptOut.wordCount == 160)

        let leftOut = WeeklyReflectionEligibilityEngine.evaluate(entries: [snapshot(words: 160, exclusion: .excludedFromAIAndReflection)], in: period)
        #expect(leftOut.kind == .empty)
        #expect(leftOut.entryCount == 0)
    }
}
