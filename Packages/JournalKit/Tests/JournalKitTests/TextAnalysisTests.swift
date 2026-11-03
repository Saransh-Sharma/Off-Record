import Foundation
import Testing
@testable import SemanticMemoryKit
import ReflectionKit

/// The shared sentiment scorer and entity extractor that replaced the app's
/// per-screen NLTagger copies.
struct TextAnalysisTests {

    // MARK: Sentiment

    @Test func languageScoreIsNilForEmptyText() {
        #expect(SentimentScorer.languageScore(for: "") == nil)
        #expect(SentimentScorer.languageScore(for: "   \n ") == nil)
        #expect(SentimentScorer.score("") == 0)
    }

    @Test func languageScoreReadsPositiveAndNegativeWording() throws {
        let positive = try #require(SentimentScorer.languageScore(for: "What a wonderful, happy day. I loved every minute with my friends."))
        let negative = try #require(SentimentScorer.languageScore(for: "This was a terrible, miserable day. Everything went wrong and I hated it."))
        #expect(positive > 0)
        #expect(negative < 0)
        #expect((-1...1).contains(positive))
        #expect((-1...1).contains(negative))
    }

    @Test func languageScoreReadsEveryParagraph() throws {
        let positive = "What a wonderful, happy day. I loved every minute with my friends."
        let negative = "This was a terrible, miserable night. Everything went wrong and I hated it."
        let firstOnly = try #require(SentimentScorer.languageScore(for: positive))
        let both = try #require(SentimentScorer.languageScore(for: positive + "\n\n" + negative))
        // A heavy second paragraph pulls the score down instead of being ignored.
        #expect(both < firstOnly)
    }

    @Test func moodWeightedScoreMatchesReflectionSentiment() {
        let samples: [(String, String?)] = [
            ("terrible stress", "happy"),
            ("wonderful day", "angry"),
            ("I feel happy and grateful and calm", nil),
            ("stress and regret and worry", nil),
            ("went to the shop", nil),
            ("tired again", "tired"),
        ]
        for (text, mood) in samples {
            #expect(SentimentScorer.moodWeightedScore(text: text, mood: mood) == ReflectionSentiment.score(text: text, mood: mood))
        }
        #expect(SentimentScorer.moodWeightedScore(text: "anything", mood: "calm") == 0.25)
    }

    // MARK: Entities

    @Test func nameOccurrencesKeepRepeatsInReadingOrder() {
        let occurrences = EntityExtractor.nameOccurrences(in: "Dinner with Maya in Bangalore. Later Maya called again.")
        let mayas = occurrences.filter { $0.text == "Maya" }
        #expect(mayas.count == 2)
        #expect(mayas.allSatisfy { $0.kind == .person })
        #expect(occurrences.contains { $0.text == "Bangalore" && $0.kind == .place })
    }

    @Test func namedEntitiesAndPersonalNamesAreDistinct() {
        let text = "Dinner with Maya in Bangalore. Later Maya called again."
        let entities = EntityExtractor.namedEntities(in: text)
        #expect(entities.filter { $0.text == "Maya" }.count == 1)
        #expect(EntityExtractor.personalNames(in: text) == ["Maya"])
    }

    @Test func extractEntitiesStaysSortedAndUnique() {
        let entities = TextSignals.extractEntities(from: "Maya and Arjun met in Bangalore. Maya laughed.")
        #expect(entities == entities.sorted())
        #expect(Set(entities).count == entities.count)
        #expect(entities.contains("Maya"))
    }

    @Test func emptyTextHasNoEntitiesOrWords() {
        #expect(EntityExtractor.nameOccurrences(in: "").isEmpty)
        #expect(EntityExtractor.words(in: "").isEmpty)
        #expect(EntityExtractor.nouns(in: "").isEmpty)
    }

    // MARK: Topics

    @Test func nounsKeepRepeatsAndDropCommonWords() {
        let nouns = EntityExtractor.nouns(in: "The project deadline moved again, and the project review felt endless.")
        #expect(nouns.filter { $0 == "project" }.count == 2)
        #expect(nouns.contains("deadline"))
        #expect(!nouns.contains("the"))
        #expect(nouns.allSatisfy { $0 == $0.lowercased() && $0.count >= 4 })
    }

    @Test func nounsHonorCustomStopWordsAndLength() {
        let nouns = EntityExtractor.nouns(in: "The project deadline moved again.", minimumLength: 8, excluding: ["deadline"])
        #expect(!nouns.contains("deadline"))
        #expect(!nouns.contains("project"))
    }

    @Test func wordsMarkMidSentenceCapitals() {
        let words = EntityExtractor.words(in: "Yesterday I walked with Maya.")
        let first = words.first { $0.text == "Yesterday" }
        let maya = words.first { $0.text == "Maya" }
        #expect(first?.isMidSentence == false)
        #expect(maya?.isMidSentence == true)
        if maya?.lexicalKind == .noun {
            #expect(maya?.nameKind == .person)
        }
    }
}
