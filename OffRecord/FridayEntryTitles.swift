//
//  FridayEntryTitles.swift
//  OffRecord
//
//  A short title per entry, written by the on-device model and shown in the
//  entry header and on Timeline cards. Titles are sentence case: the Voice
//  standard keeps Title Case for app chrome (navigation titles, buttons,
//  headers) and puts generated content (Friday's speech, insight titles) in
//  sentence case, and a title about someone's day is content.
//
//  Titles are cached by entry ID and last edit, never in Core Data. Without
//  a model, or when a title fails validation, the entry shows as it always
//  has: no title. High-risk entries never get one and never reach the model.
//

import Combine
import Foundation
import JournalFoundation
import SemanticMemoryKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Generator seam

protocol EntryTitleGenerating: Sendable {
    /// Returns nil when no model is available. Throws when the model ran and failed.
    func title(for context: EntryGenerationContext) async throws -> String?
}

// MARK: - Validation

enum EntryTitleValidator {
    static let maximumWords = 6
    static let minimumWords = 2
    private static let pronouns: Set<String> = ["i", "i'm", "me", "my", "mine", "myself", "you", "your", "yours"]

    /// The title as it will be shown, or nil when it breaks a rule.
    static func validated(_ raw: String, context: EntryGenerationContext) -> String? {
        var title = FridayOutputValidator.normalized(raw)
        while let last = title.last, ".,;:".contains(last) {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespaces)
        guard (minimumWords...maximumWords).contains(FridayOutputValidator.wordCount(title)) else { return nil }
        guard !title.contains(where: { "?.:;".contains($0) }) else { return nil }
        guard title.first?.isUppercase == true else { return nil }
        let lowered = FridayOutputValidator.words(in: title)
        guard !lowered.contains(where: pronouns.contains) else { return nil }
        guard FridayOutputValidator.isAcceptable(title) else { return nil }
        // Sentence case and grounding: capitals past the first word must be names from the entry.
        guard FridayOutputValidator.inventedNames(in: title, source: context.text).isEmpty else { return nil }
        guard FridayOutputValidator.inventedTopics(in: title, source: context.text).isEmpty else { return nil }
        guard FridayOutputValidator.sharesContent(title, with: context.text) else { return nil }
        return title
    }
}

// MARK: - Store

@MainActor
final class EntryTitleStore: ObservableObject {
    static let shared = EntryTitleStore()

    /// Shorter entries read fine without a title.
    static let minimumWordCount = 15
    /// Scrolling a long Timeline shouldn't line up dozens of model calls.
    static let maximumQueueLength = 24

    /// Bumped when a title arrives, so cards re-read.
    @Published private(set) var revision = 0

    /// Redraws titles on screen after the cache was cleared (Friday off, Erase All Data).
    func didForgetTitles() {
        revision += 1
    }

    private struct Pending {
        let key: String
        let entryID: UUID
        let context: EntryGenerationContext
        let generation: Int
    }

    private let generator: (any EntryTitleGenerating)?
    private let store: FridayGeneratedTextStore
    private let isModelAvailable: () -> Bool
    private var queue: [Pending] = []
    private var isWorking = false

    init(
        generator: (any EntryTitleGenerating)? = EntryTitleStore.systemGenerator(),
        store: FridayGeneratedTextStore? = nil,
        isModelAvailable: @escaping () -> Bool = { FridayLanguageModel.isAvailable }
    ) {
        self.generator = generator
        self.store = store ?? FridayGeneratedTextCache.titles
        self.isModelAvailable = isModelAvailable
    }

    /// The cached title for the entry as it is now, if there is one.
    func title(for entry: DiaryEntry) -> String? {
        guard let id = entry.id, FridayEntryIntelligence.isEligible(entry) else { return nil }
        return title(entryID: id, updatedAt: entry.updatedAt, text: entry.text ?? "")
    }

    func title(entryID: UUID, updatedAt: Date?, text: String) -> String? {
        guard let value = store.value(for: Self.key(entryID: entryID, updatedAt: updatedAt, text: text)), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Asks for a title if the entry has none yet. Cheap to call on every appear.
    func requestTitle(for entry: DiaryEntry) {
        guard let id = entry.id, FridayEntryIntelligence.isEligible(entry) else { return }
        requestTitle(entryID: id, updatedAt: entry.updatedAt, text: entry.text ?? "", mood: Mood(rawValue: entry.value(forKey: "mood") as? String ?? "") ?? .none)
    }

    func requestTitle(entryID: UUID, updatedAt: Date?, text: String, mood: Mood) {
        guard generator != nil, isModelAvailable() else { return }
        // High-risk text never reaches the model.
        guard FridayEntryIntelligence.mayGenerate(about: text) else { return }
        guard FridayOutputValidator.wordCount(text) >= Self.minimumWordCount else { return }
        let key = Self.key(entryID: entryID, updatedAt: updatedAt, text: text)
        guard store.value(for: key) == nil, !queue.contains(where: { $0.key == key }) else { return }
        queue.removeAll { $0.entryID == entryID }
        queue.append(Pending(key: key, entryID: entryID, context: EntryGenerationContext(text: text, mood: mood), generation: store.generation))
        if queue.count > Self.maximumQueueLength {
            queue.removeFirst(queue.count - Self.maximumQueueLength)
        }
        pump()
    }

    /// Waits until queued titles are done (tests).
    func waitUntilIdle() async {
        while isWorking || !queue.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func pump() {
        guard !isWorking, !queue.isEmpty, let generator else { return }
        let next = queue.removeFirst()
        isWorking = true
        Task { @MainActor [weak self] in
            let outcome: String?
            do {
                outcome = try await generator.title(for: next.context).map {
                    EntryTitleValidator.validated($0, context: next.context) ?? ""
                }
            } catch {
                outcome = ""
            }
            guard let self else { return }
            // A cache cleared meanwhile (Friday off, journal erased) drops the title.
            if let outcome, self.store.generation == next.generation {
                self.store.set(outcome, for: next.key, replacingPrefix: next.entryID.uuidString + "|")
                if !outcome.isEmpty { self.revision += 1 }
            }
            self.isWorking = false
            self.pump()
        }
    }

    /// Entry ID, last edit, and a short text hash, so any change asks again.
    static func key(entryID: UUID, updatedAt: Date?, text: String) -> String {
        let textHash = TextSignals.hash(text.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(12)
        return FridayGeneratedTextCache.titleKey(entryID: entryID, updatedAt: updatedAt) + "|" + textHash
    }

    nonisolated static func systemGenerator() -> (any EntryTitleGenerating)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsEntryTitleGenerator()
        }
        #endif
        return nil
    }
}

// MARK: - Foundation Models

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedEntryTitle {
    @Guide(description: "A title of 2 to 6 words in sentence case, with no punctuation at the end.")
    let title: String
}

@available(iOS 26.0, *)
struct FoundationModelsEntryTitleGenerator: EntryTitleGenerating {
    static let instructions = """
    You are Friday, the companion in a private journal app. You write a short title for one journal entry.
    Rules:
    - 2 to 6 words in sentence case: capitalize only the first word and names.
    - Say what the entry is about using only names, places, and topics from the entry. Never invent anything.
    - No pronouns such as I, me, my, you, or your.
    - No punctuation at the end, no quotation marks, no emoji.
    - Use plain, calm words. Never use these words: gentle, journey, safe space, valid, brave, self-care, just, simply, actually, unlock, thread.
    - Never use clinical or diagnostic words.
    """

    func title(for context: EntryGenerationContext) async throws -> String? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: context.promptBlock + "\n\nWrite the title.",
            generating: GeneratedEntryTitle.self,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 40)
        )
        return response.content.title
    }
}
#endif
