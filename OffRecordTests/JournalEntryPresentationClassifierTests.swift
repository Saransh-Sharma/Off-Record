import Foundation
import Testing
@testable import OffRecord

struct JournalEntryPresentationClassifierTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func sameTimestampTextAndAudioUseSingleEntryLayout() {
        let date = makeDate(hour: 10, minute: 5)
        let blocks = [
            JournalEntryPresentationBlock(kind: .text, createdAt: date),
            JournalEntryPresentationBlock(kind: .audio, createdAt: date)
        ]

        #expect(JournalEntryPresentationClassifier.layout(for: blocks, calendar: calendar) == .singleEntry)
    }

    @Test func textBlocksAtDifferentTimesUseMultiEntryLayout() {
        let blocks = [
            JournalEntryPresentationBlock(kind: .text, createdAt: makeDate(hour: 9, minute: 0)),
            JournalEntryPresentationBlock(kind: .text, createdAt: makeDate(hour: 15, minute: 30))
        ]

        #expect(JournalEntryPresentationClassifier.layout(for: blocks, calendar: calendar) == .multiEntry)
    }

    @Test func contextualMoodInSameSessionStaysSingleEntry() {
        let date = makeDate(hour: 12, minute: 31)
        let captureID = UUID()
        let blocks = [
            JournalEntryPresentationBlock(kind: .audio, createdAt: date, sourceCaptureID: captureID),
            JournalEntryPresentationBlock(kind: .text, createdAt: date, sourceCaptureID: captureID),
            JournalEntryPresentationBlock(kind: .mood, createdAt: date, sourceCaptureID: captureID)
        ]

        #expect(JournalEntryPresentationClassifier.layout(for: blocks, calendar: calendar) == .singleEntry)
    }

    @Test func separateMoodOrPhotoMomentUsesMultiEntryLayout() {
        let blocks = [
            JournalEntryPresentationBlock(kind: .text, createdAt: makeDate(hour: 9, minute: 0)),
            JournalEntryPresentationBlock(kind: .mood, createdAt: makeDate(hour: 18, minute: 0)),
            JournalEntryPresentationBlock(kind: .photo, createdAt: makeDate(hour: 18, minute: 1))
        ]

        #expect(JournalEntryPresentationClassifier.layout(for: blocks, calendar: calendar) == .multiEntry)
    }

    @Test func duplicateVisibleTimesKeepStableChronologicalOrder() {
        let first = JournalEntryPresentationBlock(kind: .text, createdAt: makeDate(hour: 13, minute: 0))
        let second = JournalEntryPresentationBlock(kind: .audio, createdAt: makeDate(hour: 13, minute: 0))
        let third = JournalEntryPresentationBlock(kind: .mood, createdAt: makeDate(hour: 13, minute: 1))

        let ordered = JournalEntryPresentationClassifier.orderedBlocks([third, first, second])

        #expect(ordered == [first, second, third])
    }

    @Test func mixedCaptureIDPresenceIsOrderIndependent() {
        let captureID = UUID()
        let text = JournalEntryPresentationBlock(kind: .text, createdAt: makeDate(hour: 10, minute: 0), sourceCaptureID: captureID)
        let audio = JournalEntryPresentationBlock(kind: .audio, createdAt: makeDate(hour: 10, minute: 0))

        let textFirst = JournalEntryPresentationClassifier.layout(for: [text, audio], calendar: calendar)
        let audioFirst = JournalEntryPresentationClassifier.layout(for: [audio, text], calendar: calendar)

        #expect(textFirst == .multiEntry)
        #expect(audioFirst == .multiEntry)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 5
        components.day = 28
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
