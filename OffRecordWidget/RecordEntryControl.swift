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
                Label("Record Entry", systemImage: "mic.fill")
            }
        }
        .displayName("Record Entry")
        .description("Starts a recording in OffRecord.")
    }
}
