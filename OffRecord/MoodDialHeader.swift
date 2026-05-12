import SwiftUI

struct MoodDialHeader: View {
    let canSave: Bool
    let cancel: () -> Void
    let done: () -> Void

    var body: some View {
        ZStack {
            Text("How are\nyou feeling?")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(OffRecordColor.textHeading)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .frame(maxWidth: 160)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button("Cancel", action: cancel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OffRecordColor.brandPlum)
                    .frame(width: 96, height: 52)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Color.black.opacity(0.045), radius: 8, y: 3)
                    .accessibilityIdentifier("moodDial.cancel")

                Spacer()

                Button("Done", action: done)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 100, height: 52)
                    .background(OffRecordColor.brandPlum.opacity(canSave ? 1 : 0.62), in: Capsule())
                    .shadow(color: Color.black.opacity(0.045), radius: 8, y: 3)
                    .accessibilityHint(canSave ? "Saves the selected mood." : "Closes without changing the mood.")
                    .accessibilityIdentifier("moodDial.done")
            }
        }
        .frame(height: 76)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
