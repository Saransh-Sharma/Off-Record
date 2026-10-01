//
//  FridayGoDeeper.swift
//  OffRecord
//
//  Go Deeper's question. When Apple Intelligence is available, the on-device
//  model writes one question grounded in the entry; it must pass
//  `GoDeeperQuestionValidator` or the deterministic `EntryFollowUpQuestion`
//  templates are used. Heavy (gentle) and high-risk entries get no question
//  and never reach the model. The first question per entry text is cached,
//  so reopening an entry shows the same one.
//

import Foundation
import JournalFoundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Generator seam

/// Writes a Go Deeper question for an entry.
protocol EntryQuestionGenerating: Sendable {
    /// Returns nil when no model is available, so nothing is cached and a later
    /// open can try again. Throws when the model ran and failed.
    func question(for context: EntryGenerationContext) async throws -> String?
}

// MARK: - Validation

enum GoDeeperQuestionValidator {
    /// "Prompt: one question, ≤10 words" (Voice, Length).
    static let maximumWords = 10
    static let minimumWords = 3
    /// Lowercased with straight apostrophes, as `FridayOutputValidator.words` returns them.
    private static let pronouns: Set<String> = ["i", "i'm", "i've", "i'd", "i'll", "me", "my", "mine", "myself"]

    /// The question as it will be shown, or nil when it breaks a rule.
    static func validated(_ raw: String, context: EntryGenerationContext) -> String? {
        let question = FridayOutputValidator.normalized(raw)
        let words = FridayOutputValidator.wordCount(question)
        guard (minimumWords...maximumWords).contains(words) else { return nil }
        // One question: it ends with the only question mark and has no other sentence.
        guard question.hasSuffix("?"), question.filter({ $0 == "?" }).count == 1 else { return nil }
        guard !question.dropLast().contains(where: { ".:;".contains($0) }) else { return nil }
        guard question.first?.isUppercase == true else { return nil }
        // Friday asks about the person, not herself.
        let lowered = FridayOutputValidator.words(in: question)
        guard !lowered.contains(where: pronouns.contains) else { return nil }
        guard FridayOutputValidator.isAcceptable(question) else { return nil }
        // Grounded: names and topics come from the entry, and it's about something in it.
        guard FridayOutputValidator.inventedNames(in: question, source: context.text).isEmpty else { return nil }
        guard FridayOutputValidator.inventedTopics(in: question, source: context.text).isEmpty else { return nil }
        guard FridayOutputValidator.sharesContent(question, with: context.text) else { return nil }
        return question
    }
}

// MARK: - Provider

@MainActor
final class GoDeeperQuestionProvider {
    static let shared = GoDeeperQuestionProvider()

    private let generator: (any EntryQuestionGenerating)?
    private let store: FridayGeneratedTextStore
    private let isModelAvailable: () -> Bool

    init(
        generator: (any EntryQuestionGenerating)? = GoDeeperQuestionProvider.systemGenerator(),
        store: FridayGeneratedTextStore? = nil,
        isModelAvailable: @escaping () -> Bool = { FridayLanguageModel.isAvailable }
    ) {
        self.generator = generator
        self.store = store ?? FridayGeneratedTextCache.questions
        self.isModelAvailable = isModelAvailable
    }

    /// The first question for this entry, or nil when the entry gets none
    /// (gentle or support-only text). `allowsModel` is false when Friday is
    /// off or the entry is kept out of Friday.
    func firstQuestion(text: String, mood: Mood, allowsModel: Bool = true) async -> String? {
        guard JournalRiskClassifier.responseMode(for: text) == .normal else { return nil }
        if allowsModel, let question = await modelQuestion(text: text, mood: mood) {
            return question
        }
        return EntryFollowUpQuestion.make(text: text, mood: mood)
    }

    /// A different question from the templates, never the one on screen.
    func nextQuestion(text: String, mood: Mood, excluding previous: String?) -> String? {
        guard JournalRiskClassifier.responseMode(for: text) == .normal else { return nil }
        return EntryFollowUpQuestion.make(text: text, mood: mood, excluding: previous)
    }

    private func modelQuestion(text: String, mood: Mood) async -> String? {
        let key = FridayGeneratedTextCache.questionKey(text: text, mood: mood)
        if let cached = store.value(for: key) {
            return cached.isEmpty ? nil : cached
        }
        guard let generator, isModelAvailable() else { return nil }

        let context = EntryGenerationContext(text: text, mood: mood)
        let generation = store.generation
        let raw: String?
        do {
            raw = try await generator.question(for: context)
        } catch {
            if store.generation == generation { store.set("", for: key) }
            return nil
        }
        // Nil means no model ran; leave the cache empty so a later open can try.
        // A cache cleared meanwhile (Friday off, journal erased) drops the answer.
        guard let raw, store.generation == generation else { return nil }
        let question = GoDeeperQuestionValidator.validated(raw, context: context)
        store.set(question ?? "", for: key)
        return question
    }

    nonisolated static func systemGenerator() -> (any EntryQuestionGenerating)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsEntryQuestionGenerator()
        }
        #endif
        return nil
    }
}

// MARK: - Foundation Models

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedFollowUpQuestion {
    @Guide(description: "One follow-up question of 4 to 10 words that ends with a question mark.")
    let question: String
}

@available(iOS 26.0, *)
struct FoundationModelsEntryQuestionGenerator: EntryQuestionGenerating {
    static let instructions = """
    You are Friday, the companion in a private journal app. You write one follow-up question about the entry the person just wrote.
    Rules:
    - Exactly one question of 4 to 10 words, in sentence case, ending with a question mark.
    - Ask about one specific thing in the entry. Use only names, places, and topics that appear in the entry. Never invent people, events, places, or feelings.
    - Talk to the person as you. Never say I, me, or my.
    - Use plain, calm words. No advice, praise, or reassurance. No exclamation marks, emoji, or quotation marks.
    - Never use these words: gentle, journey, safe space, valid, brave, self-care, just, simply, actually, unlock, thread.
    - Never use clinical or diagnostic words.
    """

    func question(for context: EntryGenerationContext) async throws -> String? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: context.promptBlock + "\n\nWrite the question.",
            generating: GeneratedFollowUpQuestion.self,
            options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 60)
        )
        return response.content.question
    }
}
#endif
