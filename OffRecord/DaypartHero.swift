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
        // App Store screenshots show a 9:41 status bar, so keep the hero and greeting in the morning.
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotMode") { return .morning }
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
        let components = imageName.split(separator: "_").map(String.init)
        let dayPartName: String?
        if components.count >= 3, components[0] == "home", components[1] == "bg" {
            dayPartName = components[2]
        } else {
            dayPartName = components.first
        }
        guard let dayPartName,
              let dayPart = DayPart(rawValue: dayPartName) else {
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
        "home_bg_morning_01",
        "home_bg_morning_02",
        "home_bg_morning_03",
        "home_bg_afternoon_01",
        "home_bg_afternoon_02",
        "home_bg_afternoon_03",
        "home_bg_evening_01",
        "home_bg_evening_02",
        "home_bg_evening_03",
        "home_bg_night_01",
        "home_bg_night_02",
        "home_bg_night_03"
    ].compactMap(DaypartHeroAsset.init(imageName:))

    static let prompts: [HeroPromptVariant] = [
        .init(id: "morning_empty_begin_softly", dayPart: .morning, useCase: .noEntryYet, title: String(localized: "Intention", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What would make today a good day?"), supportingLine: nil),
        .init(id: "morning_empty_quiet_start", dayPart: .morning, useCase: .noEntryYet, title: String(localized: "Focus", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you want more of today?"), supportingLine: nil),
        .init(id: "morning_empty_check_in", dayPart: .morning, useCase: .noEntryYet, title: String(localized: "Check-in", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "How are you starting the day?"), supportingLine: nil),
        .init(id: "morning_empty_protect_energy", dayPart: .morning, useCase: .noEntryYet, title: String(localized: "Energy", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What’s worth your energy today?"), supportingLine: nil),
        .init(id: "morning_empty_clear_start", dayPart: .morning, useCase: .noEntryYet, title: String(localized: "Priority", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What matters most this morning?"), supportingLine: nil),
        .init(id: "morning_empty_where_you_are", dayPart: .morning, useCase: .noEntryYet, title: String(localized: "Needs", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you need today?"), supportingLine: nil),
        .init(id: "morning_full_keep_thread", dayPart: .morning, useCase: .hasEntryAlready, title: String(localized: "Follow-up", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What’s still on your mind from this morning?"), supportingLine: nil),
        .init(id: "morning_full_recenter", dayPart: .morning, useCase: .hasEntryAlready, title: String(localized: "Focus", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you want to come back to today?"), supportingLine: nil),
        .init(id: "morning_full_hold_onto_this", dayPart: .morning, useCase: .hasEntryAlready, title: String(localized: "Keep", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What from this morning do you want to keep?"), supportingLine: nil),

        .init(id: "afternoon_empty_midday_reset", dayPart: .afternoon, useCase: .noEntryYet, title: String(localized: "Reset", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What can you let go of before tonight?"), supportingLine: nil),
        .init(id: "afternoon_empty_center", dayPart: .afternoon, useCase: .noEntryYet, title: String(localized: "Check-in", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What would help you feel steady right now?"), supportingLine: nil),
        .init(id: "afternoon_empty_energy_check", dayPart: .afternoon, useCase: .noEntryYet, title: String(localized: "Energy", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you need for the next few hours?"), supportingLine: nil),
        .init(id: "afternoon_empty_recalibrate", dayPart: .afternoon, useCase: .noEntryYet, title: String(localized: "Update", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What’s changed since this morning?"), supportingLine: nil),
        .init(id: "afternoon_empty_small_win", dayPart: .afternoon, useCase: .noEntryYet, title: String(localized: "Small Win", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What’s gone better than expected today?"), supportingLine: nil),
        .init(id: "afternoon_empty_lighten_load", dayPart: .afternoon, useCase: .noEntryYet, title: String(localized: "Load", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What feels heavier than it should?"), supportingLine: nil),
        .init(id: "afternoon_full_follow_up", dayPart: .afternoon, useCase: .hasEntryAlready, title: String(localized: "Follow-up", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What feels different now?"), supportingLine: nil),
        .init(id: "afternoon_full_readjust", dayPart: .afternoon, useCase: .hasEntryAlready, title: String(localized: "Adjust", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What needs to change for the rest of today?"), supportingLine: nil),
        .init(id: "afternoon_full_friction", dayPart: .afternoon, useCase: .hasEntryAlready, title: String(localized: "Friction", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What’s draining you right now?"), supportingLine: nil),

        .init(id: "evening_empty_todays_moment", dayPart: .evening, useCase: .noEntryYet, title: String(localized: "Highlight", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you want to remember about today?"), supportingLine: nil),
        .init(id: "evening_empty_stayed_with_you", dayPart: .evening, useCase: .noEntryYet, title: String(localized: "Stuck With You", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What moment from today stuck with you?"), supportingLine: nil),
        .init(id: "evening_empty_one_good_thing", dayPart: .evening, useCase: .noEntryYet, title: String(localized: "Good Thing", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What are you glad happened today?"), supportingLine: nil),
        .init(id: "evening_empty_meaningful_moment", dayPart: .evening, useCase: .noEntryYet, title: String(localized: "Yourself", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "When did you feel most like yourself today?"), supportingLine: nil),
        .init(id: "evening_empty_before_slips", dayPart: .evening, useCase: .noEntryYet, title: String(localized: "Don’t Lose It", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What would you regret not writing down?"), supportingLine: nil),
        .init(id: "evening_empty_gentle_review", dayPart: .evening, useCase: .noEntryYet, title: String(localized: "Progress", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What did you handle better than before?"), supportingLine: nil),
        .init(id: "evening_full_one_more_layer", dayPart: .evening, useCase: .hasEntryAlready, title: String(localized: "Add", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "Anything else worth adding?"), supportingLine: nil),
        .init(id: "evening_full_lingers", dayPart: .evening, useCase: .hasEntryAlready, title: String(localized: "Afterthought", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What stayed with you after writing?"), supportingLine: nil),
        .init(id: "evening_full_round_out", dayPart: .evening, useCase: .hasEntryAlready, title: String(localized: "Remember", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What else from today should you remember?"), supportingLine: nil),

        .init(id: "night_empty_close_loop", dayPart: .night, useCase: .noEntryYet, title: String(localized: "Let Go", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What are you ready to leave behind tonight?"), supportingLine: nil),
        .init(id: "night_empty_softer_ending", dayPart: .night, useCase: .noEntryYet, title: String(localized: "Tomorrow", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What can wait until tomorrow?"), supportingLine: nil),
        .init(id: "night_empty_let_it_rest", dayPart: .night, useCase: .noEntryYet, title: String(localized: "Set It Down", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What can you stop thinking about tonight?"), supportingLine: nil),
        .init(id: "night_empty_release_note", dayPart: .night, useCase: .noEntryYet, title: String(localized: "Loose Ends", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What’s unfinished but okay to pause?"), supportingLine: nil),
        .init(id: "night_empty_kind", dayPart: .night, useCase: .noEntryYet, title: String(localized: "Tonight", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you need more of tonight?"), supportingLine: nil),
        .init(id: "night_empty_before_sleep", dayPart: .night, useCase: .noEntryYet, title: String(localized: "Remember", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What do you want to remember from today?"), supportingLine: nil),
        .init(id: "night_full_close_gently", dayPart: .night, useCase: .hasEntryAlready, title: String(localized: "Last Thought", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "One last thought before bed?"), supportingLine: nil),
        .init(id: "night_full_let_today_end", dayPart: .night, useCase: .hasEntryAlready, title: String(localized: "Replay", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What are you ready to stop replaying?"), supportingLine: nil),
        .init(id: "night_full_set_it_down", dayPart: .night, useCase: .hasEntryAlready, title: String(localized: "Set It Down", comment: "Short label above a writing prompt on the Today screen"), prompt: String(localized: "What can you leave here tonight?"), supportingLine: nil)
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
