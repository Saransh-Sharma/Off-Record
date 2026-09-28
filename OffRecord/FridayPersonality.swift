//
//  FridayPersonality.swift
//  OffRecord
//
//  Shared voice and copy for Friday.
//

import Foundation

enum FridayPersonality {
    static let insufficientData = "I don’t have enough to go on yet. A few more entries will help."

    /// The intro card title and the first half of the welcome line.
    static let greeting = "I’m Friday."

    /// The intro card body. No final period, so a first name can follow.
    static let invitation = "Tell me what’s on your mind, or ask what I’ve noticed"

    /// The one welcome line, shared by the chat and the persona.
    static let welcome = "\(greeting) \(invitation)."

    static let exclusionRespected = "I don’t have anything on that."

    static let riskSafeSupport = "That sounds heavy. Talking to someone you trust could help."

    /// Friday states what she sees without a lead-in. Kept so callers compile.
    static func noticed(_ text: String) -> String {
        text
    }

    /// Friday doesn't add a sign-off. Kept so callers compile.
    static func watching(_ text: String) -> String {
        text
    }

    static func welcome(name: String) -> String {
        "\(greeting) \(Personalization.appendFirstName(to: invitation, name: name))."
    }
}
