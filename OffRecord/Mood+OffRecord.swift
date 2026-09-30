//
//  Mood+OffRecord.swift
//  OffRecord
//
//  App-side wiring for the shared MoodDialKit: re-exports the package so the
//  rest of the app keeps seeing `Mood` without per-file imports, maps
//  OffRecord's pastel palette onto the dial theme, and adapts HapticManager
//  to the shared haptics seam.
//

@_exported import MoodDialKit
import JournalFoundation
import SwiftUI

extension Mood {
    var color: Color {
        switch self {
        case .none: return OffRecordColor.textTertiary
        case .happy: return OffRecordColor.moodGreat
        case .calm: return OffRecordColor.moodCalm
        case .grateful: return OffRecordColor.moodGood
        case .excited: return OffRecordColor.moodOkay
        case .tired: return OffRecordColor.moodTired
        case .anxious: return OffRecordColor.moodAnxious
        case .sad: return OffRecordColor.moodSad
        case .angry: return OffRecordColor.moodAngry
        }
    }

    var dialSegmentColor: Color {
        switch self {
        case .none: return OffRecordColor.moodOkay
        case .happy: return OffRecordColor.moodGreat
        case .calm: return OffRecordColor.moodCalm
        case .grateful: return OffRecordColor.moodGood
        case .excited: return OffRecordColor.moodOkay
        case .tired: return OffRecordColor.moodTired
        case .anxious: return OffRecordColor.moodAnxious
        case .sad: return OffRecordColor.moodSad
        case .angry: return OffRecordColor.moodAngry
        }
    }

    var readableStyle: OffRecordReadableTintStyle {
        switch self {
        case .none:
            return .neutral
        case .happy:
            return .growth
        case .calm:
            return .growth
        case .grateful:
            return .privacy
        case .excited:
            return .highlight
        case .tired:
            return .journal
        case .anxious:
            return .friday
        case .sad:
            return .blush
        case .angry:
            return .warning
        }
    }
}

extension MoodDialTheme {
    /// OffRecord's pastel dial identity — matches the pre-extraction visuals
    /// exactly.
    static let offRecord = MoodDialTheme(
        backgroundTop: OffRecordColor.backgroundPrimary,
        backgroundBottom: OffRecordColor.backgroundSecondary,
        accent: OffRecordColor.brandPlum,
        accentContrast: .white,
        surface: OffRecordColor.backgroundPrimary,
        heading: OffRecordColor.textHeading,
        textSecondary: OffRecordColor.textSecondary,
        textTertiary: OffRecordColor.textTertiary,
        titleFont: OffRecordTypography.screenTitle,
        labelFont: OffRecordTypography.labelLarge,
        captionFont: OffRecordTypography.bodySmall,
        segmentColor: { $0.dialSegmentColor },
        moodAccent: { $0.color }
    )
}

/// Bridges the shared haptics seam onto OffRecord's HapticManager.
struct OffRecordJournalHaptics: JournalHapticsProviding {
    func selectionChanged() { HapticManager.shared.selectionChanged() }
    func moodSelected() { HapticManager.shared.moodSelected() }
    func buttonTap() { HapticManager.shared.buttonTap() }
    func recordingStarted() { HapticManager.shared.recordingStarted() }
    func recordingStopped() { HapticManager.shared.recordingStopped() }
    func entrySaved() { HapticManager.shared.entrySaved() }
    func warning() { HapticManager.shared.warning() }
    func error() { HapticManager.shared.error() }
}

extension View {
    /// Applies OffRecord's dial theme and haptics to any MoodDialKit surface.
    func offRecordMoodDialEnvironment() -> some View {
        environment(\.moodDialTheme, .offRecord)
            .environment(\.journalHaptics, OffRecordJournalHaptics())
    }
}
