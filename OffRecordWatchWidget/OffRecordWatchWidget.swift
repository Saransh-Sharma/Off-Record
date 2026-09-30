import AppIntents
import SwiftUI
import WidgetKit

struct QuickCaptureWidgetEntry: TimelineEntry {
    let date: Date
    let queueCount: Int
}

struct QuickCaptureWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureWidgetEntry {
        QuickCaptureWidgetEntry(date: Date(), queueCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> QuickCaptureWidgetEntry {
        let defaults = UserDefaults(suiteName: "group.com.singularity.offrecord")
        return QuickCaptureWidgetEntry(
            date: Date(),
            queueCount: defaults?.integer(forKey: "offrecord.watch.queueCount") ?? 0
        )
    }
}

struct OffRecordWatchWidgetEntryView: View {
    let entry: QuickCaptureWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus")
                    .font(.headline.weight(.heavy))
            }
            .widgetURL(URL(string: "offrecordwatch://home?source=complication"))
            .accessibilityLabel("Quick Capture")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quick Capture")
                        .font(.headline.weight(.semibold))
                    Text(entry.queueCount == 0 ? "All synced" : "\(entry.queueCount) waiting on watch")
                        .font(.caption2)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "offrecordwatch://home?source=smartStack"))
            .accessibilityLabel("Quick Capture")
        default:
            Text("Capture")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "offrecordwatch://home?source=smartStack"))
        }
    }
}

struct OffRecordWatchWidget: Widget {
    let kind = "OffRecordWatchQuickCapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureWidgetProvider()) { entry in
            OffRecordWatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Capture")
        .description("Opens OffRecord for a quick capture.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct OffRecordWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        OffRecordWatchWidget()
    }
}
