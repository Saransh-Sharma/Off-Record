import Foundation

enum JournalEntryPresentationLayout: Equatable {
    case singleEntry
    case multiEntry
}

struct JournalEntryPresentationBlock: Equatable {
    let kind: JournalBlockKind
    let createdAt: Date
    let sourceCaptureID: UUID?

    init(kind: JournalBlockKind, createdAt: Date, sourceCaptureID: UUID? = nil) {
        self.kind = kind
        self.createdAt = createdAt
        self.sourceCaptureID = sourceCaptureID
    }
}

enum JournalEntryPresentationClassifier {
    static func layout(
        for blocks: [JournalEntryPresentationBlock],
        calendar: Calendar = .current
    ) -> JournalEntryPresentationLayout {
        let blocks = orderedBlocks(blocks)
        guard !blocks.isEmpty else { return .singleEntry }

        let primaryBlocks = blocks.filter(\.isPrimaryJournalMoment)
        guard !primaryBlocks.isEmpty else {
            return blocks.count <= 1 ? .singleEntry : .multiEntry
        }

        guard primaryBlocks.count <= 2 else { return .multiEntry }
        guard allBlocksShareSession(primaryBlocks, calendar: calendar) else { return .multiEntry }
        guard allBlocksShareSession(blocks, calendar: calendar) else { return .multiEntry }

        return .singleEntry
    }

    static func orderedBlocks(_ blocks: [JournalEntryPresentationBlock]) -> [JournalEntryPresentationBlock] {
        blocks.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt < rhs.element.createdAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func allBlocksShareSession(
        _ blocks: [JournalEntryPresentationBlock],
        calendar: Calendar
    ) -> Bool {
        guard let first = blocks.first else { return true }

        let captureIDs = blocks.compactMap(\.sourceCaptureID)
        if !captureIDs.isEmpty {
            guard captureIDs.count == blocks.count, let firstCaptureID = captureIDs.first else {
                return false
            }
            return captureIDs.allSatisfy { $0 == firstCaptureID }
        }

        return blocks.allSatisfy {
            calendar.isDate($0.createdAt, equalTo: first.createdAt, toGranularity: .minute)
        }
    }
}

private extension JournalEntryPresentationBlock {
    var isPrimaryJournalMoment: Bool {
        kind == .text || kind == .audio
    }
}
