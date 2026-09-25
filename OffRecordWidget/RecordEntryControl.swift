//
//  RecordEntryControl.swift
//  OffRecordWidget
//
//  Control Center, Lock Screen, and Action Button control that opens
//  OffRecord and starts a voice capture.
//

import AppIntents
import SwiftUI
import WidgetKit

struct RecordEntryControl: ControlWidget {
    static let kind = "com.singularity.offrecord.control.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RecordJournalIntent()) {
                Label("Record entry", systemImage: "mic.fill")
            }
        }
        .displayName("Record entry")
        .description("Start a private voice entry in OffRecord.")
    }
}
