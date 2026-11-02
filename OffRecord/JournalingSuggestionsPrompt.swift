//
//  JournalingSuggestionsPrompt.swift
//  OffRecord
//
//  Apple's Journaling Suggestions as a prompt source on Today. Picking a
//  suggestion opens a typed note on today's entry with the suggestion as its
//  prompt, and attaches the suggestion's photos, up to the import limit.
//
//  The picker needs iPhone hardware and the com.apple.developer.journal.allow
//  entitlement: the framework isn't in the Simulator SDK and doesn't run on
//  iPad, so the button only exists there. The rest compiles everywhere.
//

import SwiftUI
import UIKit
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

/// A picked suggestion reduced to what OffRecord keeps: a prompt and photo files.
struct JournalingSuggestionDraft: Equatable, Sendable {
    var title: String
    var reflectionPrompts: [String]
    var photoURLs: [URL]

    /// A reflection prompt when the suggestion has one, otherwise its title.
    var prompt: String? {
        let candidates = reflectionPrompts + [title]
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The photos one pick may add to the entry.
    var photosToImport: [URL] {
        JournalPhotoImport.capped(photoURLs)
    }
}

@MainActor
enum JournalingSuggestionsPrompt {
    /// Journaling Suggestions run on iPhone only.
    static var isAvailable: Bool {
        #if canImport(JournalingSuggestions)
        return UIDevice.current.userInterfaceIdiom == .phone && !ProcessInfo.processInfo.isiOSAppOnMac
        #else
        return false
        #endif
    }

    /// Attaches the draft's photos to today's entry, then opens the typed note with its prompt.
    static func start(with draft: JournalingSuggestionDraft) async {
        let photoData = draft.photosToImport.compactMap { try? Data(contentsOf: $0) }
        if !photoData.isEmpty {
            let capture = CaptureController.shared
            let capturedAt = capture.captureTimestamp()
            if let entry = capture.getOrCreateEntry(capturedAt: capturedAt) {
                await JournalPhotoImport.attach(
                    photoData,
                    to: entry,
                    capturedAt: capturedAt,
                    in: PersistenceController.shared.container.viewContext
                )
            }
        }
        OffRecordNavigationRouter.shared.requestTypedNote(promptContext: draft.prompt)
    }
}

/// Opens the Journaling Suggestions picker. Renders nothing where suggestions aren't available.
struct JournalingSuggestionsButton: View {
    var body: some View {
        #if canImport(JournalingSuggestions)
        if JournalingSuggestionsPrompt.isAvailable {
            JournalingSuggestionsPicker {
                Label(String(localized: "Pick a Suggestion", comment: "Button that opens Apple’s Journaling Suggestions"), systemImage: "sparkles.rectangle.stack")
                    .offRecordReadablePill(.journal)
                    .frame(minHeight: OffRecordLayout.minimumTapTarget)
            } onCompletion: { suggestion in
                let draft = await JournalingSuggestionDraft(suggestion)
                await JournalingSuggestionsPrompt.start(with: draft)
            }
            .accessibilityHint(String(localized: "Opens Journaling Suggestions to start an entry."))
            .accessibilityIdentifier("today.journalingSuggestions")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }
}

#if canImport(JournalingSuggestions)
extension JournalingSuggestionDraft {
    /// Reads the parts OffRecord uses while the picker's files are still available.
    init(_ suggestion: JournalingSuggestion) async {
        let reflections = await suggestion.content(forType: JournalingSuggestion.Reflection.self)
        let photos = await suggestion.content(forType: JournalingSuggestion.Photo.self)
        let livePhotos = await suggestion.content(forType: JournalingSuggestion.LivePhoto.self)
        self.init(
            title: suggestion.title,
            reflectionPrompts: reflections.map(\.prompt),
            photoURLs: photos.map(\.photo) + livePhotos.map(\.image)
        )
    }
}
#endif
