//
//  RecordingElsewhereNote.swift
//  OffRecord
//
//  What an entry shows for a recording whose audio isn't on this device.
//  Audio never syncs (entries and transcripts do), so the file stays with the
//  device that saved it. The only device signal in the store is a watch
//  capture's ID and `watch-` file name, so other recordings say "another device".
//

import SwiftUI

/// Where a recording was made, as far as the store can tell.
enum RecordingOrigin: Equatable {
    /// Recorded on Apple Watch; the iPhone that imported it holds the audio.
    case appleWatch
    /// Recorded on an iPhone, iPad, or Mac. The store doesn't say which.
    case anotherDevice

    init(fileName: String?, sourceCaptureID: UUID?) {
        if sourceCaptureID != nil || fileName?.hasPrefix("watch-") == true {
            self = .appleWatch
        } else {
            self = .anotherDevice
        }
    }

    var systemImage: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .anotherDevice: return "icloud.slash"
        }
    }

    var title: String {
        switch self {
        case .appleWatch:
            return String(localized: "Recorded on Apple Watch", comment: "Entry: a recording whose audio is on another device")
        case .anotherDevice:
            return String(localized: "Recorded on Another Device", comment: "Entry: a recording whose audio is on another device")
        }
    }

    /// One line that says why the audio isn't here and where to play it.
    var explanation: String {
        switch self {
        case .appleWatch:
            return String(localized: "Recordings don’t sync, so play it on the iPhone that saved it.")
        case .anotherDevice:
            return String(localized: "Recordings don’t sync, so play it on the device that recorded it.")
        }
    }
}

/// Replaces the player when a recording's file isn't on this device.
struct RecordingElsewhereNote: View {
    let origin: RecordingOrigin
    let duration: TimeInterval

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OffRecordSpacing.sm) {
            Image(systemName: origin.systemImage)
                .foregroundStyle(OffRecordColor.textSky)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                Text(headline)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                Text(origin.explanation)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("entryDetail.recordingElsewhere")
    }

    private var headline: String {
        guard duration > 0 else { return origin.title }
        return "\(origin.title) · \(Self.formattedDuration(duration))"
    }

    static func formattedDuration(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 {
            return String(localized: "\(minutes)m \(seconds)s", comment: "Short recording length in minutes and seconds.")
        }
        return String(localized: "\(seconds)s", comment: "Short recording length in seconds.")
    }
}

extension JournalBlockTimelineItem {
    /// Where this recording was made, when its audio isn't on this device.
    var recordingElsewhereOrigin: RecordingOrigin? {
        guard kind == .audio, !audioExists else { return nil }
        return RecordingOrigin(fileName: audioURL?.lastPathComponent, sourceCaptureID: sourceCaptureID)
    }

    /// Read after the block's label, since the block row sets its own.
    var recordingElsewhereAccessibilityValue: String {
        recordingElsewhereOrigin.map { "\($0.title). \($0.explanation)" } ?? ""
    }
}
