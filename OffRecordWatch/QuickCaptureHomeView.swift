import SwiftUI

struct QuickCaptureHomeView: View {
    @ObservedObject var store: WatchCaptureStore
    @State private var path: [WatchHomeRoute] = []
    @State private var sourceSurface: WatchCaptureSourceSurface = .app

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WatchScreenBackground(mood: .plum)

                VStack(alignment: .leading, spacing: 10) {
                    header

                    QuickCaptureActionCard(
                        title: "Mood capture",
                        subtitle: "Capture how you feel",
                        systemImage: "leaf.fill",
                        fill: WatchPalette.mintSurface,
                        foreground: WatchPalette.sageText,
                        decoration: .leaf
                    ) {
                        path.append(.mood)
                    }

                    QuickCaptureActionCard(
                        title: "Speak",
                        subtitle: "Save a voice thought",
                        systemImage: "quote.bubble.fill",
                        fill: WatchPalette.lavenderSurface,
                        foreground: WatchPalette.lavenderText,
                        decoration: .waveform
                    ) {
                        path.append(.speak)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .navigationDestination(for: WatchHomeRoute.self) { route in
                switch route {
                case .mood:
                    WatchMoodCaptureView(store: store, source: sourceSurface)
                case .speak, .record:
                    WatchSpeakCaptureView(store: store, source: sourceSurface)
                case .recent:
                    WatchRecentCapturesView(store: store)
                case .home:
                    EmptyView()
                }
            }
            .onOpenURL(perform: handleOpenURL)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("OffRecord")
                .font(.caption.bold())
                .foregroundStyle(WatchPalette.mutedText)
            Text("Quick Capture")
                .font(.title3.bold())
                .foregroundStyle(WatchPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private func handleOpenURL(_ url: URL) {
        guard let route = WatchHomeRoute(url: url) else { return }
        sourceSurface = WatchHomeRoute.sourceSurface(from: url)
        path = route == .home ? [] : [route]
    }
}
