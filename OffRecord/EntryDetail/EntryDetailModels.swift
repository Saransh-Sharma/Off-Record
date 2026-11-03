//
//  EntryDetailModels.swift
//  OffRecord
//
//  Value types behind the entry detail screen: its date formatters, the
//  save decision, and the timeline item each block row draws from.
//

import SwiftUI
import CoreData

enum EntryDetailDateFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "MMM d",
            options: 0,
            locale: formatter.locale
        )
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "EEEE MMMM d yyyy",
            options: 0,
            locale: formatter.locale
        )
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct EntryDetailSaveDecision: Equatable {
    let shouldSave: Bool
    let shouldSaveText: Bool
    let skippedStaleTextOverwrite: Bool

    static func evaluate(
        localText: String,
        persistedText: String,
        hasEditedText: Bool,
        moodChanged: Bool
    ) -> EntryDetailSaveDecision {
        let trimmedLocalText = localText.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedHasText = !persistedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let textChanged = trimmedLocalText != persistedText
        let skippedStaleTextOverwrite = !hasEditedText && textChanged && persistedHasText

        return EntryDetailSaveDecision(
            shouldSave: (hasEditedText && textChanged) || moodChanged,
            shouldSaveText: hasEditedText && textChanged,
            skippedStaleTextOverwrite: skippedStaleTextOverwrite
        )
    }
}

struct JournalBlockTimelineItem: Identifiable {
    let id: NSManagedObjectID
    let blockID: UUID
    let kind: JournalBlockKind
    let createdAt: Date
    let sourceCaptureID: UUID?
    let timestamp: String
    let text: String
    let mood: Mood
    let duration: TimeInterval
    let audioURL: URL?
    let audioExists: Bool
    let photoAttachmentID: UUID?

    var daypart: String {
        JournalBlockTimelinePresentation.daypart(for: createdAt)
    }

    var timeText: String {
        EntryDetailDateFormatters.time.string(from: createdAt)
    }

    var presentationBlock: JournalEntryPresentationBlock {
        JournalEntryPresentationBlock(
            kind: kind,
            createdAt: createdAt,
            sourceCaptureID: sourceCaptureID
        )
    }

    var accessibilityLabel: String {
        switch kind {
        case .text:
            return String(localized: "Text, \(timestamp)", comment: "VoiceOver label for a text block in an entry. The argument is when it was added.")
        case .audio:
            let seconds = Int(duration.rounded())
            return String(AttributedString(localized: "Recording, ^[\(seconds) second](inflect: true), \(timestamp)").characters)
        case .mood:
            return String(localized: "Mood, \(mood.displayName), \(timestamp)", comment: "VoiceOver label for a mood block in an entry. The arguments are the mood and when it was added.")
        case .photo:
            return String(localized: "Photo, \(timestamp)", comment: "VoiceOver label for a photo block in an entry. The argument is when it was added.")
        }
    }
}

extension JournalBlockTimelineItem {
    var systemImage: String {
        switch kind {
        case .text: return "square.and.pencil"
        case .audio: return "waveform"
        case .mood: return mood == .none ? "face.smiling" : mood.icon
        case .photo: return "photo"
        }
    }

    var accentColor: Color {
        switch kind {
        case .text: return OffRecordColor.textLavender
        case .audio: return OffRecordColor.textSky
        case .mood: return mood.readableStyle.foreground
        case .photo: return OffRecordColor.textPeach
        }
    }

    var nodeFill: Color {
        switch kind {
        case .text: return OffRecordColor.surfaceLavender
        case .audio: return OffRecordColor.surfaceBlue
        case .mood: return mood == .none ? OffRecordColor.surfaceSage : mood.readableStyle.fill
        case .photo: return OffRecordColor.surfacePeach
        }
    }

    var nodeBorder: Color {
        switch kind {
        case .text: return OffRecordColor.brandLavender.opacity(0.42)
        case .audio: return OffRecordColor.brandSky.opacity(0.48)
        case .mood: return mood == .none ? OffRecordColor.borderSage : mood.readableStyle.border
        case .photo: return OffRecordColor.borderWarm
        }
    }

    var nodeForeground: Color {
        switch kind {
        case .text: return OffRecordColor.textBrand
        case .audio: return OffRecordColor.textSky
        case .mood: return mood == .none ? OffRecordColor.textSage : mood.readableStyle.foreground
        case .photo: return OffRecordColor.textPeach
        }
    }
}
