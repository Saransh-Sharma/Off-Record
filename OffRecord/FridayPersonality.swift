//
//  FridayPersonality.swift
//  OffRecord
//
//  Shared voice and copy for Friday.
//

import Foundation

enum FridayPersonality {
    static let insufficientData = String(localized: "I don’t have enough to go on yet. A few more entries will help.")

    /// The intro card title and the first half of the welcome line.
    static let greeting = String(localized: "I’m Friday.", comment: "Friday introduces herself; followed by an invitation to talk")

    /// The intro card body. No final period, so a first name can follow.
    static let invitation = String(localized: "Tell me what’s on your mind, or ask what I’ve noticed", comment: "No final period: the app may add “, <first name>” and then a period")

    /// The one welcome line, shared by the chat and the persona.
    static let welcome = "\(greeting) \(invitation)."

    static let exclusionRespected = String(localized: "I don’t have anything on that.")

    static let riskSafeSupport = String(localized: "That sounds heavy. Talking to someone you trust could help.")

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
