import SwiftUI

struct MoodDialSelectedMoodView: View {
    let mood: Mood
    let layoutScale: CGFloat
    let isInteractionActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chevronPulse = false

    var body: some View {
        VStack(spacing: 12 * layoutScale) {
            Text(mood.moodSentence)
                .font(.system(size: 18 * layoutScale, weight: .medium))
                .foregroundStyle(OffRecordColor.textSecondary)
                .contentTransition(.opacity)
                .accessibilityIdentifier("moodDial.sentence")

            ZStack {
                Image(mood.moodGlowAssetName)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(width: 292 * layoutScale, height: 292 * layoutScale)
                    .opacity(0.24)
                    .accessibilityHidden(true)

                Image(mood.largeMoodAssetName)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(width: 160 * layoutScale, height: 160 * layoutScale)
                    .scaleEffect(reduceMotion ? 1 : 1.035)
                    .accessibilityLabel(mood.displayName)
                    .accessibilityIdentifier("moodDial.largeIcon")
            }
            .frame(width: 220 * layoutScale, height: 176 * layoutScale)

            Text(mood.supportiveCopy)
                .font(.system(size: 15 * layoutScale, weight: .regular))
                .foregroundStyle(OffRecordColor.textTertiary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)

            Image(systemName: "chevron.compact.down")
                .font(.system(size: 40 * layoutScale, weight: .heavy))
                .foregroundStyle(OffRecordColor.textTertiary.opacity(0.70))
                .offset(y: reduceMotion ? 0 : (chevronPulse ? 5 : 0))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
                    value: chevronPulse
                )
                .accessibilityHidden(true)
        }
        .animation(selectedMoodAnimation, value: mood)
        .onAppear {
            guard !reduceMotion else { return }
            chevronPulse = true
        }
    }

    private var selectedMoodAnimation: Animation? {
        if reduceMotion {
            return .easeInOut(duration: 0.18)
        }

        if isInteractionActive {
            return nil
        }

        return .spring(response: 0.28, dampingFraction: 0.72)
    }
}
