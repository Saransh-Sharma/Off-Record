//
//  OffRecordCommands.swift
//  OffRecord
//
//  Menu bar commands for Mac and for iPad with a keyboard: Write (⌘N),
//  Record (⇧⌘R), Search (⌘F), and on Mac, Settings (⌘,). They do nothing
//  while onboarding, Lock, or the store recovery screen is showing.
//

import SwiftUI

struct OffRecordCommands: Commands {
    /// False during onboarding, while locked, or when the store didn't open.
    let canNavigate: Bool
    @ObservedObject var router: OffRecordNavigationRouter
    @ObservedObject var capture: CaptureController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Write", comment: "Menu command (⌘N) that starts a typed entry")) {
                router.requestTypedNote()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!canNavigate || capture.phase.isCapturing)

            Button(capture.phase.isCapturing
                ? String(localized: "Stop Recording", comment: "Menu command (⇧⌘R) that ends the current recording")
                : String(localized: "Record", comment: "Menu command (⇧⌘R) that starts a voice recording")) {
                capture.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!canNavigate || capture.phase == .starting)
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button(String(localized: "Search Entries", comment: "Menu command (⌘F) that opens Timeline search")) {
                router.requestTimelineSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!canNavigate)
        }

        #if targetEnvironment(macCatalyst)
        // iPad keeps the system's Settings item, which opens the Settings app.
        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "Settings", comment: "Mac app menu command (⌘,) that opens the Settings tab")) {
                router.selectedTab = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!canNavigate)
        }
        #endif
    }
}
