import SwiftUI

struct WatchScreenBackground: View {
    enum Mood {
        case plum
        case sage
        case lavender
        case peach

        var colors: [Color] {
            switch self {
            case .plum:
                return [WatchPalette.midnightPlum, WatchPalette.deepPlum, WatchPalette.darkSage]
            case .sage:
                return [WatchPalette.deepPlum, WatchPalette.plum, WatchPalette.darkSage]
            case .lavender:
                return [WatchPalette.midnightPlum, WatchPalette.deepPlum, WatchPalette.lavenderShadow]
            case .peach:
                return [WatchPalette.deepPlum, WatchPalette.plum, WatchPalette.peachShadow]
            }
        }
    }

    let mood: Mood

    var body: some View {
        LinearGradient(
            colors: mood.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
