import SwiftUI

struct QuickCaptureActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let fill: Color
    let foreground: Color
    let decoration: Decoration
    let action: () -> Void

    enum Decoration {
        case leaf
        case waveform
    }

    var body: some View {
        Button(action: handleTap) {
            ZStack(alignment: .trailing) {
                decorationView
                    .padding(.trailing, 6)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.48))
                            .frame(width: 38, height: 38)
                        Image(systemName: systemImage)
                            .font(.headline.bold())
                            .foregroundStyle(foreground)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text(subtitle)
                            .font(.caption)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(foreground.opacity(0.62))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(.white.opacity(0.42), lineWidth: 1)
            }
        }
        .buttonStyle(WatchPressButtonStyle())
        .accessibilityLabel("\(title). \(subtitle)")
    }

    @ViewBuilder
    private var decorationView: some View {
        switch decoration {
        case .leaf:
            Image(systemName: "leaf.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(foreground.opacity(0.08))
                .rotationEffect(.degrees(-18))
        case .waveform:
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(foreground.opacity(0.09))
                        .frame(width: 5, height: CGFloat([22, 34, 46, 30, 18][index]))
                }
            }
        }
    }

    private func handleTap() {
        WatchHaptics.selection()
        action()
    }
}
