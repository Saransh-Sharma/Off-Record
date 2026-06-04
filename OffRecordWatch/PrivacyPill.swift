import SwiftUI

struct PrivacyPill: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .foregroundStyle(WatchPalette.sageText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(WatchPalette.sageSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(WatchPalette.sage.opacity(0.28), lineWidth: 1)
            }
            .accessibilityLabel(text)
    }
}
