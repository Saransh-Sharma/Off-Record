import SwiftUI

struct WatchRecentCapturesView: View {
    @ObservedObject var store: WatchCaptureStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            WatchScreenBackground(mood: .sage)

            VStack(alignment: .leading, spacing: 10) {
                header

                if store.captures.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(store.captures) { item in
                                WatchRecentCaptureRow(item: item, preview: store.preview(for: item))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .frame(width: 32, height: 32)
                    .foregroundStyle(WatchPalette.sage)
                    .background(WatchPalette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(WatchPalette.sage.opacity(0.34), lineWidth: 1)
                    }
            }
            .buttonStyle(WatchPressButtonStyle())
            .accessibilityLabel("Back")

            Text("Recent")
                .font(.headline.bold())
                .foregroundStyle(WatchPalette.text)

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(WatchPalette.sageSurface.opacity(0.92))
                    .frame(width: 58, height: 58)
                Image(systemName: "checkmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(WatchPalette.sageText)
            }
            .accessibilityHidden(true)

            Text("Nothing held")
                .font(.headline.bold())
                .foregroundStyle(WatchPalette.text)

            Text("Quick captures will appear here until they're on your iPhone.")
                .font(.caption)
                .foregroundStyle(WatchPalette.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 172)

            Spacer(minLength: 0)

            WatchEmptyLandscape()
                .frame(height: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nothing held. Quick captures will appear here until they are on your iPhone.")
    }
}

struct WatchRecentCaptureRow: View {
    let item: WatchRecentCapture
    let preview: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .foregroundStyle(color)
                .background(color.opacity(0.18), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(WatchPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Text(item.envelope.createdAtUTC, style: .time)
                    Text(statusText)
                }
                .font(.caption2.bold())
                .foregroundStyle(WatchPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(WatchPalette.softBorder, lineWidth: 1)
        }
        .accessibilityLabel("\(title), \(statusText)")
    }

    private var title: String {
        switch item.envelope.kind {
        case .mood:
            return "Mood: \(preview)"
        case .speak:
            return "Dictated note"
        case .audio:
            return "Voice moment"
        }
    }

    private var symbol: String {
        switch item.envelope.kind {
        case .mood: return "face.smiling"
        case .speak: return "quote.bubble"
        case .audio: return "waveform"
        }
    }

    private var statusText: String {
        switch item.syncState {
        case .saved, .queued:
            return "On Watch"
        case .sending:
            return "Syncing"
        case .synced:
            return "Synced"
        case .failed:
            return "Try again"
        }
    }

    private var color: Color {
        switch item.syncState {
        case .synced:
            return WatchPalette.sage
        case .failed:
            return WatchPalette.peach
        case .sending:
            return WatchPalette.lavender
        default:
            return WatchPalette.secondary
        }
    }
}

struct WatchEmptyLandscape: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(WatchPalette.lavender.opacity(0.18))
                .frame(width: 18, height: 18)
                .offset(x: 42, y: -18)

            Capsule()
                .fill(WatchPalette.lavender.opacity(0.22))
                .frame(width: 42, height: 8)
                .offset(x: -36, y: -24)

            RoundedRectangle(cornerRadius: 18)
                .fill(WatchPalette.sage.opacity(0.22))
                .frame(width: 126, height: 34)
                .offset(x: -28, y: 8)

            RoundedRectangle(cornerRadius: 18)
                .fill(WatchPalette.peach.opacity(0.20))
                .frame(width: 122, height: 28)
                .offset(x: 32, y: 10)

            HStack(spacing: 16) {
                Image(systemName: "leaf.fill")
                Image(systemName: "sparkle")
            }
            .font(.caption2.bold())
            .foregroundStyle(WatchPalette.sage.opacity(0.48))
            .offset(y: -6)
        }
        .accessibilityHidden(true)
    }
}
