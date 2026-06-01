import SwiftUI

struct WatchPrimaryButton: View {
    let title: String
    let systemImage: String
    let fill: Color
    let foreground: Color
    var isDisabled = false
    var minHeight: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .foregroundStyle(foreground)
                .background(fill, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(WatchPalette.softBorder, lineWidth: 1)
                }
        }
        .buttonStyle(WatchPressButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

struct WatchSecondaryButton: View {
    let title: String
    let systemImage: String
    var minHeight: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .foregroundStyle(WatchPalette.text)
                .background(WatchPalette.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(WatchPalette.softBorder, lineWidth: 1)
                }
        }
        .buttonStyle(WatchPressButtonStyle())
    }
}

struct WatchPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
