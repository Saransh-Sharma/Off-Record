//
//  FridayPersonality.swift
//  OffRecord
//
//  Shared voice and copy for Friday.
//

import Foundation

enum FridayPersonality {
    static let insufficientData = "I'm still learning your rhythm. Keep journaling and I'll get more useful."

    static func noticed(_ text: String) -> String {
        "I'm noticing this from your entries so far: \(text)"
    }

    static func watching(_ text: String) -> String {
        "\(text) I'll keep watching this with you."
    }

    static func welcome(name: String) -> String {
        Personalization.appendFirstName(
            to: "I'm Friday. Tell me what you're carrying, or ask what I've noticed.",
            name: name
        )
    }
}
