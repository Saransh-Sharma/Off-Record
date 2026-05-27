import SwiftUI
import WatchKit

enum WatchMoodValue: String, CaseIterable, Identifiable, Codable {
    case angry
    case sad
    case anxious
    case tired
    case calm
    case grateful
    case happy
    case excited

    var id: String { rawValue }

    static let dialOrder: [WatchMoodValue] = [
        .angry, .sad, .anxious, .tired, .calm, .grateful, .happy, .excited
    ]

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
        }
    }

    var sentence: String {
        "I feel \(displayName.lowercased())."
    }

    var supportiveCopy: String {
        switch self {
        case .happy: return "Something feels lighter."
        case .calm: return "A steady moment."
        case .grateful: return "Something mattered."
        case .excited: return "There's energy here."
        case .tired: return "Move gently."
        case .anxious: return "Come back to now."
        case .sad: return "Hold this softly."
        case .angry: return "Name it. No judgment."
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
        }
    }

    var glowAssetName: String {
        switch self {
        case .angry, .sad, .anxious, .tired:
            return "Difficult_Glow"
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
    static let plum = Color(hex: 0x342044)
    static let ink = Color(hex: 0x241730)
    static let text = Color(hex: 0xFFF8F0)
    static let secondary = Color(hex: 0xE7DDEA)
    static let sage = Color(hex: 0xA8D8BE)
    static let peach = Color(hex: 0xF6B98F)
    static let lavender = Color(hex: 0xBBA7E8)
    static let surface = Color(hex: 0xFFF8F0, opacity: 0.14)
}
