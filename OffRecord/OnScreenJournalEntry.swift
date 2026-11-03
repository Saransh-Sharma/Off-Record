//
//  OnScreenJournalEntry.swift
//  OffRecord
//
//  Tells Siri which entry is on screen, so a request like "star this" can
//  act on it. The view advertises an `NSUserActivity` that carries the
//  entry's `JournalEntryEntity` identifier, and Siri resolves it through
//  `JournalEntryQuery`, which returns metadata only (date, mood, starred,
//  word count, recording and photo presence), never entry text. The
//  activity has no title and is never donated to Spotlight, predictions or
//  Handoff.
//

import AppIntents
import SwiftUI

extension View {
    func onScreenJournalEntry(_ id: UUID?) -> some View {
        userActivity(JournalSpotlightIndexer.viewEntryActivityType, isActive: id != nil) { activity in
            guard let id else { return }
            activity.appEntityIdentifier = EntityIdentifier(for: JournalEntryEntity.self, identifier: id)
            activity.isEligibleForSearch = false
            activity.isEligibleForPrediction = false
            activity.isEligibleForHandoff = false
            activity.isEligibleForPublicIndexing = false
        }
    }
}
