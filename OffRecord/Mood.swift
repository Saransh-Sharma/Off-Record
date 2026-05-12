import SwiftUI

enum Mood: String, CaseIterable, Identifiable {
    case none = ""
    case happy = "happy"
    case calm = "calm"
    case grateful = "grateful"
    case excited = "excited"
    case tired = "tired"
    case anxious = "anxious"
    case sad = "sad"
    case angry = "angry"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No mood"
        case .happy: return "Happy"
        case .calm: return "Calm"
        case .grateful: return "Grateful"
        case .excited: return "Excited"
        case .tired: return "Tired"
        case .anxious: return "Anxious"
        case .sad: return "Sad"
        case .angry: return "Angry"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dashed"
        case .happy: return "sun.max.fill"
        case .calm: return "leaf.fill"
        case .grateful: return "heart.fill"
        case .excited: return "star.fill"
        case .tired: return "moon.zzz.fill"
        case .anxious: return "wind"
        case .sad: return "cloud.rain.fill"
        case .angry: return "flame.fill"
        }
    }

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

    static var selectableMoods: [Mood] {
        allCases.filter { $0 != .none }
    }

    static let dialMoods: [Mood] = [
        .angry,
        .sad,
        .anxious,
        .tired,
        .none,
        .calm,
        .grateful,
        .happy,
        .excited
    ]

    static var neutralDialIndex: Int {
        dialMoods.firstIndex(of: .none) ?? 0
    }

    var moodSentence: String {
        switch self {
        case .none: return "I feel neutral."
        case .happy: return "I feel happy."
        case .calm: return "I feel calm."
        case .grateful: return "I feel grateful."
        case .excited: return "I feel excited."
        case .tired: return "I feel tired."
        case .anxious: return "I feel anxious."
        case .sad: return "I feel sad."
        case .angry: return "I feel angry."
        }
    }

    var supportiveCopy: String {
        switch self {
        case .none: return "Nothing to force."
        case .happy: return "Something feels lighter."
        case .calm: return "A steady moment."
        case .grateful: return "Something mattered today."
        case .excited: return "There's energy here."
        case .tired: return "Move gently."
        case .anxious: return "Come back to now."
        case .sad: return "Hold this softly."
        case .angry: return "Name it without judging it."
        }
    }

    var largeMoodAssetName: String {
        switch self {
        case .none: return "NoMood_Neutral_Large"
        case .happy: return "Happy_Large"
        case .calm: return "Calm_Large"
        case .grateful: return "Grateful_Large"
        case .excited: return "Excited_Large"
        case .tired: return "Tired_Large"
        case .anxious: return "Anxious_Large"
        case .sad: return "Sad_Large"
        case .angry: return "Angry_Large"
        }
    }

    var miniMoodAssetName: String {
        switch self {
        case .none: return "NoMood_Neutral_Mini"
        case .happy: return "Happy_Mini"
        case .calm: return "Calm_Mini"
        case .grateful: return "Grateful_Mini"
        case .excited: return "Excited_Mini"
        case .tired: return "Tired_Mini"
        case .anxious: return "Anxious_Mini"
        case .sad: return "Sad_Mini"
        case .angry: return "Angry_Mini"
        }
    }

    var moodGlowAssetName: String {
        switch self {
        case .angry, .sad, .anxious, .tired:
            return "Difficult_Glow"
        case .none:
            return "Neutral_Glow"
        case .calm, .grateful, .happy, .excited:
            return "Positive_Glow"
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
