import SwiftUI

struct WatchMoodCaptureView: View {
    @ObservedObject var store: WatchCaptureStore
    let source: WatchCaptureSourceSurface

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var crownFocused: Bool
    @State private var index = WatchMoodValue.openingIndex
    @State private var saved = false
    @State private var isSaving = false

    private var selectedMood: WatchMoodValue {
        WatchMoodValue.dialOrder[min(max(Int(index.rounded()), 0), WatchMoodValue.dialOrder.count - 1)]
    }

    var body: some View {
        ZStack {
            WatchScreenBackground(mood: .sage)

            VStack(spacing: 8) {
                topBar
                moodHero

                MoodIconStrip(selectedMood: selectedMood) { mood in
                    select(mood)
                }

                Text(selectedMood.supportiveCopy)
                    .font(.caption.bold())
                    .foregroundStyle(WatchPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                WatchPrimaryButton(
                    title: saved ? "Saved" : "Save",
                    systemImage: saved ? "checkmark.circle.fill" : "heart.fill",
                    fill: WatchPalette.sage,
                    foreground: WatchPalette.sageText,
                    isDisabled: isSaving || saved,
                    action: saveMood
                )
                .accessibilityLabel("Save mood")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if saved {
                SaveConfirmationToast(title: "Saved")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $index,
            from: 0,
            through: Double(WatchMoodValue.dialOrder.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            crownFocused = true
        }
        .onChange(of: index) { _, _ in
            WatchHaptics.selection()
        }
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.74), value: selectedMood)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: saved)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mood capture")
        .accessibilityValue(selectedMood.displayName)
        .accessibilityHint("Turn the Digital Crown or choose a mood, then save.")
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .frame(width: 32, height: 32)
                    .foregroundStyle(WatchPalette.sage)
                    .background(WatchPalette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(WatchPalette.sage.opacity(0.34), lineWidth: 1)
                    }
            }
            .buttonStyle(WatchPressButtonStyle())
            .accessibilityLabel("Back")

            Spacer(minLength: 4)

            Text(selectedMood.sentence)
                .font(.headline.bold())
                .foregroundStyle(WatchPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.opacity)

            Spacer(minLength: 36)
        }
    }

    private var moodHero: some View {
        ZStack {
            Circle()
                .fill(selectedMood.color.opacity(0.18))
                .frame(width: 116, height: 82)
                .blur(radius: 8)

            WatchMoodSymbolMark(mood: selectedMood, size: saved ? 78 : 72)
                .shadow(color: selectedMood.color.opacity(0.26), radius: 10, y: 5)
                .accessibilityLabel(selectedMood.displayName)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
    }

    private func select(_ mood: WatchMoodValue) {
        guard let nextIndex = WatchMoodValue.dialOrder.firstIndex(of: mood) else { return }
        index = Double(nextIndex)
        WatchHaptics.selection()
    }

    private func saveMood() {
        guard !isSaving, !saved else { return }
        isSaving = true
        store.saveMood(selectedMood, source: source)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            dismiss()
        }
    }
}
