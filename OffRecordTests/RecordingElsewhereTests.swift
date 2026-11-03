import CoreData
import Foundation
import Testing
@testable import OffRecord

/// The entry row for a recording whose audio is on another device. Audio never syncs.
@MainActor
@Suite(.serialized)
struct RecordingElsewhereTests {

    private func audioItem(fileName: String?, sourceCaptureID: UUID?, exists: Bool, kind: JournalBlockKind = .audio) throws -> JournalBlockTimelineItem {
        let context = PersistenceController(inMemory: true).container.viewContext
        let block = NSEntityDescription.insertNewObject(forEntityName: "JournalBlock", into: context)
        try context.obtainPermanentIDs(for: [block])
        return JournalBlockTimelineItem(
            id: block.objectID,
            blockID: UUID(),
            kind: kind,
            createdAt: Date(),
            sourceCaptureID: sourceCaptureID,
            timestamp: "9:41 AM",
            text: "",
            mood: .none,
            duration: 72,
            audioURL: fileName.map { URL(fileURLWithPath: "/tmp/Recordings").appendingPathComponent($0) },
            audioExists: exists,
            photoAttachmentID: nil
        )
    }

    @Test func watchCapturesSayAppleWatch() {
        #expect(RecordingOrigin(fileName: "watch-6F1C.m4a", sourceCaptureID: nil) == .appleWatch)
        #expect(RecordingOrigin(fileName: "A1B2.m4a", sourceCaptureID: UUID()) == .appleWatch)
    }

    @Test func otherRecordingsSayAnotherDevice() {
        #expect(RecordingOrigin(fileName: "A1B2C3.m4a", sourceCaptureID: nil) == .anotherDevice)
        #expect(RecordingOrigin(fileName: nil, sourceCaptureID: nil) == .anotherDevice)
    }

    @Test func onlyMissingAudioGetsTheNote() throws {
        let missing = try audioItem(fileName: "watch-1.m4a", sourceCaptureID: nil, exists: false)
        #expect(missing.recordingElsewhereOrigin == .appleWatch)
        #expect(missing.recordingElsewhereAccessibilityValue.contains(RecordingOrigin.appleWatch.title))

        let here = try audioItem(fileName: "A.m4a", sourceCaptureID: nil, exists: true)
        #expect(here.recordingElsewhereOrigin == nil)
        #expect(here.recordingElsewhereAccessibilityValue.isEmpty)

        let text = try audioItem(fileName: nil, sourceCaptureID: nil, exists: false, kind: .text)
        #expect(text.recordingElsewhereOrigin == nil)
    }

    @Test func noteCopyFitsOneLine() {
        for origin in [RecordingOrigin.appleWatch, .anotherDevice] {
            let words = origin.explanation.split(whereSeparator: \.isWhitespace)
            #expect(words.count <= 12, "\(origin) explanation is \(words.count) words")
            #expect(origin.explanation.contains("don’t sync"))
            #expect(!origin.explanation.contains("!"))
        }
    }

    @Test func durationReadsLikeTheEntryHeader() {
        #expect(RecordingElsewhereNote.formattedDuration(72) == "1m 12s")
        #expect(RecordingElsewhereNote.formattedDuration(9) == "9s")
    }
}
