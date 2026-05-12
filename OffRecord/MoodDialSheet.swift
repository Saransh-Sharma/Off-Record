import SwiftUI

struct MoodDialSheet: View {
    @Binding private var selectedMood: Mood
    @Environment(\.dismiss) private var dismiss

    @State private var draftMood: Mood
    private let originalMood: Mood
    private let onSave: () -> Void

    init(selectedMood: Binding<Mood>, onSave: @escaping () -> Void) {
        let openingMood = MoodDialPersistence.openingMood(for: selectedMood.wrappedValue)
        _selectedMood = selectedMood
        _draftMood = State(initialValue: openingMood)
        originalMood = openingMood
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .top) {
            MoodDialView(selectedMood: $draftMood)

            MoodDialHeader(
                canSave: MoodDialPersistence.shouldSave(originalMood: originalMood, draftMood: draftMood),
                cancel: cancel,
                done: done
            )
            .padding(.top, 44)
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("moodDial.sheet")
    }

    private func cancel() {
        dismiss()
    }

    private func done() {
        if MoodDialPersistence.shouldSave(originalMood: originalMood, draftMood: draftMood) {
            selectedMood = draftMood
            onSave()
        }
        dismiss()
    }
}
