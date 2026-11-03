//
//  ReflectionSentiment.swift
//  ReflectionKit
//
//  Deterministic mood/keyword sentiment used across reflection surfaces.
//  The scoring itself lives in SemanticMemoryKit's SentimentScorer, the one
//  scorer both apps share.
//

import Foundation
import SemanticMemoryKit

public enum ReflectionSentiment {
    /// Delegates to the shared `SentimentScorer` so every surface scores alike.
    public static func score(text: String, mood: String?) -> Double {
        SentimentScorer.moodWeightedScore(text: text, mood: mood)
    }
}
