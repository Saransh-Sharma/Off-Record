import SwiftUI
import WatchKit

enum WatchMoodValue: String, CaseIterable, Identifiable, Codable {
    case angry
    case sad
    case anxious
    case tired
    case none = ""
    case calm
    case grateful
    case happy
    case excited

    var id: String { rawValue }

    static let dialOrder: [WatchMoodValue] = [
        .angry, .sad, .anxious, .tired, .none, .calm, .grateful, .happy, .excited
    ]

    static let openingIndex = Double(dialOrder.firstIndex(of: .calm) ?? 0)

    var displayName: String {
        switch self {
        case .happy: return "Happy"
        case .calm: return "Calm"
        case .grateful: return "Grateful"
        case .excited: return "Excited"
        case .tired: return "Tired"
        case .anxious: return "Anxious"
        case .sad: return "Sad"
        case .angry: return "Angry"
        case .none: return "Neutral"
        }
    }

    var sentence: String {
        if self == .none {
            return "I feel neutral."
        }
        return "I feel \(displayName.lowercased())."
    }

    var supportiveCopy: String {
        switch self {
        case .happy: return "Let it land."
        case .calm: return "A steady moment."
        case .grateful: return "Something mattered."
        case .excited: return "There's energy here."
        case .tired: return "Move slowly."
        case .anxious: return "Come back to now."
        case .sad: return "Hold it softly."
        case .angry: return "Name it gently."
        case .none: return "Nothing to force."
        }
    }

    var faceAssetName: String {
        switch self {
        case .happy: return "Happy_face"
        case .calm: return "Calm_face"
        case .grateful: return "Grateful_face"
        case .excited: return "Excited_face"
        case .tired: return "Sleepy_face"
        case .anxious: return "Anxious_face"
        case .sad: return "Sad_face"
        case .angry: return "Angry_face"
        case .none: return "Neutral_face"
        }
    }

    var largeAssetName: String {
        switch self {
        case .happy: return "Happy_Large"
        case .calm: return "Calm_Large"
        case .grateful: return "Grateful_Large"
        case .excited: return "Excited_Large"
        case .tired: return "Tired_Large"
        case .anxious: return "Anxious_Large"
        case .sad: return "Sad_Large"
        case .angry: return "Angry_Large"
        case .none: return "NoMood_Neutral_Large"
        }
    }

    var miniAssetName: String {
        switch self {
        case .happy: return "Happy_Mini"
        case .calm: return "Calm_Mini"
        case .grateful: return "Grateful_Mini"
        case .excited: return "Excited_Mini"
        case .tired: return "Tired_Mini"
        case .anxious: return "Anxious_Mini"
        case .sad: return "Sad_Mini"
        case .angry: return "Angry_Mini"
        case .none: return "NoMood_Neutral_Mini"
        }
    }

    var glowAssetName: String {
        switch self {
        case .angry, .sad, .anxious, .tired:
            return "Difficult_Glow"
        case .none:
            return "Neutral_Glow"
        case .calm, .grateful, .happy, .excited:
            return "Positive_Glow"
        }
    }

    var color: Color {
        switch self {
        case .happy: return Color(hex: 0xA8D8BE)
        case .calm: return Color(hex: 0x6FC6B8)
        case .grateful: return Color(hex: 0x7FA08A)
        case .excited: return Color(hex: 0xF7D98B)
        case .tired: return Color(hex: 0xF6B98F)
        case .anxious: return Color(hex: 0xBBA7E8)
        case .sad: return Color(hex: 0xF6A9B8)
        case .angry: return Color(hex: 0xEF8A7A)
        case .none: return Color(hex: 0xF7D98B)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .happy: return Color(hex: 0x4C775B)
        case .calm: return Color(hex: 0x2D7168)
        case .grateful: return Color(hex: 0x5F806B)
        case .excited, .none: return Color(hex: 0x735F1E)
        case .tired: return Color(hex: 0x8D4F1E)
        case .anxious: return Color(hex: 0x7B5CAF)
        case .sad: return Color(hex: 0x9B4357)
        case .angry: return Color(hex: 0x9F4036)
        }
    }

    var symbolName: String {
        switch self {
        case .angry: return "flame.fill"
        case .sad: return "cloud.rain.fill"
        case .anxious: return "wind"
        case .tired: return "moon.zzz.fill"
        case .none: return "circle.dashed"
        case .calm: return "leaf.fill"
        case .grateful: return "heart.fill"
        case .happy: return "face.smiling.fill"
        case .excited: return "sparkles"
        }
    }
}

enum WatchHaptics {
    static func selection() {
        WKInterfaceDevice.current().play(.click)
    }

    static func start() {
        WKInterfaceDevice.current().play(.start)
    }

    static func stop() {
        WKInterfaceDevice.current().play(.stop)
    }

    static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    static func warning() {
        WKInterfaceDevice.current().play(.retry)
    }

    static func error() {
        WKInterfaceDevice.current().play(.failure)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum WatchPalette {
    static let midnightPlum = Color(hex: 0x18131D)
    static let deepPlum = Color(hex: 0x241730)
    static let plum = Color(hex: 0x342044)
    static let ink = deepPlum
    static let darkSage = Color(hex: 0x2F4E3B)
    static let lavenderShadow = Color(hex: 0x403052)
    static let peachShadow = Color(hex: 0x523429)
    static let text = Color(hex: 0xFFF8F0)
    static let secondary = Color(hex: 0xE7DDEA)
    static let mutedText = Color(hex: 0xCFC2D7)
    static let sage = Color(hex: 0xA8D8BE)
    static let sageText = Color(hex: 0x4C775B)
    static let sageSurface = Color(hex: 0xEEF6EF)
    static let peach = Color(hex: 0xF6B98F)
    static let peachText = Color(hex: 0x8D4F1E)
    static let peachSurface = Color(hex: 0xFFF1E5)
    static let lavender = Color(hex: 0xBBA7E8)
    static let lavenderText = Color(hex: 0x342044)
    static let lavenderSurface = Color(hex: 0xF4EEFF)
    static let warmSurface = Color(hex: 0xFFF8F0)
    static let mintSurface = Color(hex: 0xEFFAF4)
    static let surface = Color(hex: 0xFFF8F0, opacity: 0.16)
    static let softBorder = Color.white.opacity(0.18)
}
