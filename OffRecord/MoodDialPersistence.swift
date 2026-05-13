enum MoodDialPersistence {
    static func openingMood(for savedMood: Mood) -> Mood {
        Mood.dialMoods.contains(savedMood) ? savedMood : .none
    }

    static func shouldSave(originalMood: Mood, draftMood: Mood) -> Bool {
        originalMood != draftMood
    }
}
