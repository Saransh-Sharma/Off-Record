//
//  Personalization.swift
//  OffRecord
//

import Foundation

enum Personalization {
    static func trimmedName(from name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstName(from name: String) -> String? {
        let trimmed = trimmedName(from: name)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    static func appendFirstName(to text: String, name: String) -> String {
        guard let firstName = firstName(from: name) else { return text }
        return "\(text), \(firstName)"
    }
}
