//
//  DaypartHero.swift
//  OffRecord
//
//  Contextual Today hero prompt selection and lightweight repetition tracking.
//

import Foundation

enum DayPart: String, CaseIterable, Codable, Identifiable {
    case morning
    case afternoon
    case evening
    case night

    var id: String { rawValue }

    static func current(for date: Date = .now, calendar: Calendar = .current) -> DayPart {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    var displayName: String {
        switch self {
        case .morning: return String(localized: "Morning")
        case .afternoon: return String(localized: "Afternoon")
        case .evening: return String(localized: "Evening")
        case .night: return String(localized: "Night")
        }
    }

    var accessibilityPromptLabel: String {
        switch self {
        case .morning: return String(localized: "Morning reflection prompt")
        case .afternoon: return String(localized: "Afternoon reflection prompt")
        case .evening: return String(localized: "Evening reflection prompt")
        case .night: return String(localized: "Night reflection prompt")
        }
    }

    var symbolName: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

enum HeroUseCase: String, Codable {
    case noEntryYet
    case hasEntryAlready
}

struct HeroPromptVariant: Identifiable, Equatable, Codable {
    let id: String
    let dayPart: DayPart
    let useCase: HeroUseCase
    let title: String
    let prompt: String
    let supportingLine: String?
    let primaryCTA: String
}

struct DaypartHeroAsset: Identifiable, Equatable, Codable {
    let id: String
    let dayPart: DayPart
    let imageName: String

    init(id: String? = nil, dayPart: DayPart, imageName: String) {
        self.id = id ?? imageName
        self.dayPart = dayPart
        self.imageName = imageName
    }

    init?(imageName: String) {
        guard let prefix = imageName.split(separator: "_").first,
              let dayPart = DayPart(rawValue: String(prefix)) else {
            return nil
        }
        self.init(dayPart: dayPart, imageName: imageName)
    }
}

struct SelectedDaypartHero: Equatable {
    let dayPart: DayPart
    let prompt: HeroPromptVariant
    let asset: DaypartHeroAsset?
}

struct DaypartHeroHistory: Codable, Equatable {
    var recentPromptIDs: [String] = []
    var recentTitles: [String] = []
    var lastImageIDByDayPart: [String: String] = [:]
    var promptSkips: [String: [Date]] = [:]
    var suppressedUntil: [String: Date] = [:]
    var affinity: [String: Int] = [:]
}

final class DaypartHeroStore {
    private let defaults: UserDefaults
    private let key: String
    private(set) var history: DaypartHeroHistory

    init(
        defaults: UserDefaults = .standard,
        key: String = "offrecord.daypartHero.history"
    ) {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DaypartHeroHistory.self, from: data) {
            history = decoded
        } else {
            history = DaypartHeroHistory()
        }
    }

    func recordExposure(_ hero: SelectedDaypartHero) {
        history.recentPromptIDs.insert(hero.prompt.id, at: 0)
        history.recentPromptIDs = Array(history.recentPromptIDs.prefix(12))

        history.recentTitles.insert(hero.prompt.title, at: 0)
        history.recentTitles = Array(history.recentTitles.prefix(5))

        if let asset = hero.asset {
            history.lastImageIDByDayPart[hero.dayPart.rawValue] = asset.id
        }
        save()
    }

    func recordSkip(promptID: String, now: Date = .now) {
        let windowStart = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        var skips = history.promptSkips[promptID, default: []].filter { $0 >= windowStart }
        skips.append(now)
        history.promptSkips[promptID] = skips

        if skips.count >= 2 {
            history.suppressedUntil[promptID] = Calendar.current.date(byAdding: .day, value: 14, to: now)
        }
        save()
    }

    func recordPromptResponse(promptID: String?, wordCount: Int) {
        guard let promptID, wordCount > 40 else { return }
        history.affinity[promptID] = min((history.affinity[promptID] ?? 0) + 1, 5)
        save()
    }

    func isSuppressed(promptID: String, now: Date = .now) -> Bool {
        guard let suppressedUntil = history.suppressedUntil[promptID] else { return false }
        return suppressedUntil > now
    }

    func reset() {
        history = DaypartHeroHistory()
        defaults.removeObject(forKey: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }
}

enum DaypartHeroLibrary {
    static let assets: [DaypartHeroAsset] = [
        "morning_01_moon_starry_clouds",
        "morning_01_sunrise_meadow_path",
        "morning_04_sunlit_window_coffee",
        "morning_05_sunrise_hills_path",
        "afternoon_01_lavender_stones_water",
        "afternoon_02_rain_cloud_heart",
        "afternoon_03_lakeside_hammock_daylight",
        "afternoon_04_park_path_trees",
        "afternoon_06_midday_cloud_hills",
        "evening_01_pink_valley_river",
        "evening_02_rainy_window_coffee",
        "evening_02_shooting_star_hills",
        "evening_03_lakeside_hammock_sunset",
        "evening_04_sunset_lake_mountains",
        "evening_05_workspace_laptop_coffee",
        "night_02_sunny_flower_meadow",
        "night_03_moon_candle_window"
    ].compactMap(DaypartHeroAsset.init(imageName:))

    static let prompts: [HeroPromptVariant] = [
        .init(id: "morning_empty_begin_softly", dayPart: .morning, useCase: .noEntryYet, title: "Begin softly", prompt: "What would make today feel worth remembering?", supportingLine: "Start with one intention.", primaryCTA: "Start morning entry"),
        .init(id: "morning_empty_quiet_start", dayPart: .morning, useCase: .noEntryYet, title: "Quiet start", prompt: "What do you want more of today?", supportingLine: "Energy, focus, calm, courage - name it simply.", primaryCTA: "Set today's tone"),
        .init(id: "morning_empty_check_in", dayPart: .morning, useCase: .noEntryYet, title: "Morning check-in", prompt: "How are you arriving into today?", supportingLine: "Tired, steady, hopeful, scattered - all of it counts.", primaryCTA: "Check in"),
        .init(id: "morning_empty_protect_energy", dayPart: .morning, useCase: .noEntryYet, title: "Protect your energy", prompt: "What do you want to protect your energy for today?", supportingLine: "A quiet nudge before the day fills up.", primaryCTA: "Record intention"),
        .init(id: "morning_empty_clear_start", dayPart: .morning, useCase: .noEntryYet, title: "A clear start", prompt: "What matters most this morning?", supportingLine: "Name the thing you do not want to lose sight of.", primaryCTA: "Write the focus"),
        .init(id: "morning_empty_where_you_are", dayPart: .morning, useCase: .noEntryYet, title: "Start where you are", prompt: "What do you need from yourself today?", supportingLine: "Meet the day honestly.", primaryCTA: "Begin entry"),
        .init(id: "morning_full_keep_thread", dayPart: .morning, useCase: .hasEntryAlready, title: "Keep the thread", prompt: "What still feels most true from this morning?", supportingLine: nil, primaryCTA: "Add note"),
        .init(id: "morning_full_recenter", dayPart: .morning, useCase: .hasEntryAlready, title: "Recenter", prompt: "What do you want to return to today?", supportingLine: nil, primaryCTA: "Add reflection"),
        .init(id: "morning_full_hold_onto_this", dayPart: .morning, useCase: .hasEntryAlready, title: "Hold onto this", prompt: "What part of your morning do you want to carry forward?", supportingLine: nil, primaryCTA: "Save thought"),

        .init(id: "afternoon_empty_midday_reset", dayPart: .afternoon, useCase: .noEntryYet, title: "Midday reset", prompt: "What can you let go of before the day continues?", supportingLine: "Pause. Name it. Move forward lighter.", primaryCTA: "Record a reset"),
        .init(id: "afternoon_empty_center", dayPart: .afternoon, useCase: .noEntryYet, title: "Come back to center", prompt: "What would help you feel grounded again?", supportingLine: "A small pause can change the rest of the day.", primaryCTA: "Check in now"),
        .init(id: "afternoon_empty_energy_check", dayPart: .afternoon, useCase: .noEntryYet, title: "Energy check", prompt: "What do you need for the next few hours?", supportingLine: "Less pressure, more honesty.", primaryCTA: "Add midday note"),
        .init(id: "afternoon_empty_recalibrate", dayPart: .afternoon, useCase: .noEntryYet, title: "Recalibrate", prompt: "What has changed since this morning?", supportingLine: "Let the day update the story.", primaryCTA: "Reflect now"),
        .init(id: "afternoon_empty_small_win", dayPart: .afternoon, useCase: .noEntryYet, title: "Small win so far", prompt: "What is one thing that has gone better than expected today?", supportingLine: "Do not miss the good in the middle of the day.", primaryCTA: "Capture it"),
        .init(id: "afternoon_empty_lighten_load", dayPart: .afternoon, useCase: .noEntryYet, title: "Lighten the load", prompt: "What feels heavier than it needs to right now?", supportingLine: "Write it down and make space around it.", primaryCTA: "Offload thought"),
        .init(id: "afternoon_full_follow_up", dayPart: .afternoon, useCase: .hasEntryAlready, title: "Midday follow-up", prompt: "What feels different now?", supportingLine: nil, primaryCTA: "Add update"),
        .init(id: "afternoon_full_readjust", dayPart: .afternoon, useCase: .hasEntryAlready, title: "Re-adjust", prompt: "What needs to change for the rest of the day?", supportingLine: nil, primaryCTA: "Add reset"),
        .init(id: "afternoon_full_friction", dayPart: .afternoon, useCase: .hasEntryAlready, title: "Name the friction", prompt: "What is draining your energy right now?", supportingLine: nil, primaryCTA: "Add note"),

        .init(id: "evening_empty_todays_moment", dayPart: .evening, useCase: .noEntryYet, title: "Today's moment", prompt: "What small win from today do you want to remember?", supportingLine: "Capture it before it fades.", primaryCTA: "Save today's moment"),
        .init(id: "evening_empty_stayed_with_you", dayPart: .evening, useCase: .noEntryYet, title: "What stayed with you", prompt: "What moment from today still feels alive?", supportingLine: "Start with the part that lingers.", primaryCTA: "Reflect now"),
        .init(id: "evening_empty_one_good_thing", dayPart: .evening, useCase: .noEntryYet, title: "One good thing", prompt: "What are you glad happened today?", supportingLine: "Even small things count.", primaryCTA: "Record gratitude"),
        .init(id: "evening_empty_meaningful_moment", dayPart: .evening, useCase: .noEntryYet, title: "Meaningful moment", prompt: "When did you feel most like yourself today?", supportingLine: "That moment is worth keeping.", primaryCTA: "Write it down"),
        .init(id: "evening_empty_before_slips", dayPart: .evening, useCase: .noEntryYet, title: "Before the day slips away", prompt: "What would you regret not writing down today?", supportingLine: "One line can be enough.", primaryCTA: "Start entry"),
        .init(id: "evening_empty_gentle_review", dayPart: .evening, useCase: .noEntryYet, title: "Gentle review", prompt: "What did you handle better than before?", supportingLine: "Notice your own progress.", primaryCTA: "Add reflection"),
        .init(id: "evening_full_one_more_layer", dayPart: .evening, useCase: .hasEntryAlready, title: "One more layer", prompt: "Is there a small win you want to add?", supportingLine: nil, primaryCTA: "Add note"),
        .init(id: "evening_full_lingers", dayPart: .evening, useCase: .hasEntryAlready, title: "What lingers", prompt: "What stayed with you after writing?", supportingLine: nil, primaryCTA: "Continue entry"),
        .init(id: "evening_full_round_out", dayPart: .evening, useCase: .hasEntryAlready, title: "Round out the day", prompt: "What else deserves to be remembered?", supportingLine: nil, primaryCTA: "Add reflection"),

        .init(id: "night_empty_close_loop", dayPart: .night, useCase: .noEntryYet, title: "Close the loop", prompt: "What are you ready to leave behind tonight?", supportingLine: "Write it down. Let the day end.", primaryCTA: "Wind down with Friday"),
        .init(id: "night_empty_softer_ending", dayPart: .night, useCase: .noEntryYet, title: "Softer ending", prompt: "What thought deserves a gentler ending?", supportingLine: "You do not need to carry everything into sleep.", primaryCTA: "Add a night note"),
        .init(id: "night_empty_let_it_rest", dayPart: .night, useCase: .noEntryYet, title: "Let it rest", prompt: "What can you stop holding for today?", supportingLine: "The page can hold it for you.", primaryCTA: "Offload now"),
        .init(id: "night_empty_release_note", dayPart: .night, useCase: .noEntryYet, title: "Release note", prompt: "What feels unfinished, but okay to pause?", supportingLine: "Not everything needs closing tonight.", primaryCTA: "Write and release"),
        .init(id: "night_empty_kind", dayPart: .night, useCase: .noEntryYet, title: "Be kind to yourself", prompt: "What do you need more of tonight?", supportingLine: "Gentleness counts too.", primaryCTA: "Check in"),
        .init(id: "night_empty_before_sleep", dayPart: .night, useCase: .noEntryYet, title: "Before sleep", prompt: "What do you want Friday to remember from today?", supportingLine: "Let the day settle into one clear note.", primaryCTA: "Capture the day"),
        .init(id: "night_full_close_gently", dayPart: .night, useCase: .hasEntryAlready, title: "Close gently", prompt: "Is there one last thought you want to leave on the page?", supportingLine: nil, primaryCTA: "Add note"),
        .init(id: "night_full_let_today_end", dayPart: .night, useCase: .hasEntryAlready, title: "Let today end", prompt: "What are you ready to stop replaying tonight?", supportingLine: nil, primaryCTA: "Add reflection"),
        .init(id: "night_full_set_it_down", dayPart: .night, useCase: .hasEntryAlready, title: "Set it down", prompt: "What can you leave here instead of taking to sleep?", supportingLine: nil, primaryCTA: "Write once more")
    ]

    static func prompts(dayPart: DayPart, useCase: HeroUseCase) -> [HeroPromptVariant] {
        prompts.filter { $0.dayPart == dayPart && $0.useCase == useCase }
    }

    static func selectHero(
        dayPart: DayPart,
        hasEntryToday: Bool,
        store: DaypartHeroStore,
        now: Date = .now,
        randomIndex: ((Int) -> Int)? = nil
    ) -> SelectedDaypartHero {
        let useCase: HeroUseCase = hasEntryToday ? .hasEntryAlready : .noEntryYet
        let matchingPrompts = prompts(dayPart: dayPart, useCase: useCase)
        let unsuppressed = matchingPrompts.filter { !store.isSuppressed(promptID: $0.id, now: now) }
        let availablePrompts = unsuppressed.isEmpty ? matchingPrompts : unsuppressed

        let recentPrompt = store.history.recentPromptIDs.first
        let recentTitles = Set(store.history.recentTitles.prefix(5))
        let freshPrompts = availablePrompts.filter {
            $0.id != recentPrompt && !recentTitles.contains($0.title)
        }
        let promptPool = freshPrompts.isEmpty ? availablePrompts : freshPrompts
        let selectedPrompt = weightedPrompt(from: promptPool, store: store, randomIndex: randomIndex)
            ?? matchingPrompts[0]

        let matchingAssets = assets.filter { $0.dayPart == dayPart }
        let lastImageID = store.history.lastImageIDByDayPart[dayPart.rawValue]
        let freshAssets = matchingAssets.count > 1
            ? matchingAssets.filter { $0.id != lastImageID }
            : matchingAssets
        let assetPool = freshAssets.isEmpty ? matchingAssets : freshAssets
        let selectedAsset = pick(from: assetPool, randomIndex: randomIndex)

        return SelectedDaypartHero(dayPart: dayPart, prompt: selectedPrompt, asset: selectedAsset)
    }

    private static func weightedPrompt(
        from prompts: [HeroPromptVariant],
        store: DaypartHeroStore,
        randomIndex: ((Int) -> Int)?
    ) -> HeroPromptVariant? {
        guard !prompts.isEmpty else { return nil }
        let weighted = prompts.flatMap { prompt in
            Array(repeating: prompt, count: 1 + (store.history.affinity[prompt.id] ?? 0))
        }
        return pick(from: weighted, randomIndex: randomIndex)
    }

    private static func pick<T>(from values: [T], randomIndex: ((Int) -> Int)?) -> T? {
        guard !values.isEmpty else { return nil }
        let index = randomIndex?(values.count) ?? Int.random(in: 0..<values.count)
        return values[max(0, min(values.count - 1, index))]
    }
}
