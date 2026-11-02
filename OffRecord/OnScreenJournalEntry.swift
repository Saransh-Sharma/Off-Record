//
//  OnScreenJournalEntry.swift
//  OffRecord
//
//  Tells Siri which entry is on screen, so a request like "star this" can
//  act on it. Siri gets the entry's `JournalEntryEntity` identifier and
//  resolves it through `JournalEntryQuery`, which returns metadata only
//  (date, mood, starred, word count, recording and photo presence), never
//  entry text. The modifier is iOS 18.4 API, so it needs no availability
//  check at the iOS 26 deployment target.
//

import AppIntents
import SwiftUI

extension View {
    func onScreenJournalEntry(_ id: UUID?) -> some View {
        appEntityIdentifier(id.map { EntityIdentifier(for: JournalEntryEntity.self, identifier: $0) })
    }
}
