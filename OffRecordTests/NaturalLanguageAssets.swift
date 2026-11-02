import Foundation
import NaturalLanguage

/// Apple's language data (the name tagger and sentence embeddings) is a
/// downloadable asset. A fresh simulator can't fetch it ("client is not
/// entitled" for com.apple.linguisticdata), so every word tags as Other and
/// `sentenceEmbedding(for:)` is nil. Tests that need the data skip there
/// instead of failing; they still run wherever the data is present.
enum NaturalLanguageAssets {
    static let tagsNames: Bool = {
        let text = "Dinner with Maya in Bangalore helped me feel grounded."
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var foundPerson = false
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .joinNames]
        ) { tag, _ in
            if tag == .personalName { foundPerson = true }
            return !foundPerson
        }
        return foundPerson
    }()

    static let hasSentenceEmbeddings: Bool = NLEmbedding.sentenceEmbedding(for: .english) != nil
}
