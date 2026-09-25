//
//  CaptureLiveActivity.swift
//  OffRecordWidget
//
//  Lock Screen and Dynamic Island presentation for an in-progress voice
//  capture. Shows timing and controls only; never a prompt or transcript.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct CaptureLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            CaptureLockScreenView(state: context.state)
                .activityBackgroundTint(OffRecordColor.backgroundPrimary)
                .activitySystemActionForegroundColor(OffRecordColor.textPrimary)
                .widgetURL(OffRecordWidgetRoute.record)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.isPaused ? "Paused" : "Recording")
                            .font(OffRecordWidgetTypography.label)
                    } icon: {
                        RecordingIndicator(isPaused: context.state.isPaused, size: 10)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptureTimerText(state: context.state)
                        .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        PrivacyLabel()
                            .foregroundStyle(.white.opacity(0.72))
                        Spacer(minLength: 4)
                        PauseResumeButton(isPaused: context.state.isPaused, fill: .white.opacity(0.16), foreground: .white)
                        StopCaptureButton()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                RecordingIndicator(isPaused: context.state.isPaused, size: 10)
                    .padding(.leading, 2)
            } compactTrailing: {
                CaptureTimerText(state: context.state)
                    .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(context.state.isPaused ? .white.opacity(0.7) : OffRecordColor.recording)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OffRecordColor.recording)
                    .accessibilityLabel(context.state.isPaused ? "Recording paused" : "Recording")
            }
            .keylineTint(OffRecordColor.recording)
            .widgetURL(OffRecordWidgetRoute.record)
        }
    }
}

struct CaptureLockScreenView: View {
    let state: CaptureActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(OffRecordColor.recording.opacity(0.16))
                Image(systemName: state.isPaused ? "pause.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OffRecordColor.recording)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.isPaused ? "Paused" : "Recording")
                    .font(OffRecordWidgetTypography.label)
                    .foregroundStyle(OffRecordColor.textSecondary)
                CaptureTimerText(state: state)
                    .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OffRecordColor.textHeading)
                    .lineLimit(1)
                PrivacyLabel()
                    .foregroundStyle(OffRecordColor.textSecondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                PauseResumeButton(isPaused: state.isPaused, fill: OffRecordColor.surfaceLavender, foreground: OffRecordColor.textBrand)
                StopCaptureButton()
            }
        }
        .padding(16)
    }
}

/// Counts up while recording; freezes on the paused duration.
struct CaptureTimerText: View {
    let state: CaptureActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(Duration.seconds(state.pausedElapsed), format: .time(pattern: .minuteSecond))
                .accessibilityLabel("Paused at \(Duration.seconds(state.pausedElapsed).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))")
        } else {
            Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false, showsHours: false)
        }
    }
}

struct RecordingIndicator: View {
    let isPaused: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: size + 1, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Circle()
                    .fill(OffRecordColor.recording)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(isPaused ? "Recording paused" : "Recording")
    }
}

struct PrivacyLabel: View {
    var body: some View {
        Label("Private · on this device", systemImage: "lock.fill")
            .font(OffRecordWidgetTypography.micro)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

struct PauseResumeButton: View {
    let isPaused: Bool
    let fill: Color
    let foreground: Color

    var body: some View {
        Button(intent: ToggleCapturePauseIntent()) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Resume recording" : "Pause recording")
    }
}

struct StopCaptureButton: View {
    var body: some View {
        Button(intent: StopCaptureIntent()) {
            Image(systemName: "stop.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(OffRecordColor.recording))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop and save recording")
    }
}

#Preview("Live Activity", as: .content, using: CaptureActivityAttributes()) {
    CaptureLiveActivityWidget()
} contentStates: {
    CaptureActivityAttributes.ContentState(startDate: Date().addingTimeInterval(-83), isPaused: false, pausedElapsed: 0)
    CaptureActivityAttributes.ContentState(startDate: Date(), isPaused: true, pausedElapsed: 83)
}
