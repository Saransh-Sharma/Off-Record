import SwiftUI

struct SaveConfirmationToast: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.caption.bold())
            .foregroundStyle(WatchPalette.sageText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(WatchPalette.sageSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(WatchPalette.sage.opacity(0.36), lineWidth: 1)
            }
            .accessibilityLabel(title)
    }
}
