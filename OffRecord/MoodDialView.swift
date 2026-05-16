import SwiftUI

struct MoodDialView: View {
    @Binding var selectedMood: Mood
    @State private var isWheelDragging = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = MoodDialWheelMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                LinearGradient(
                    colors: [OffRecordColor.backgroundPrimary, OffRecordColor.backgroundSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                MoodDialSelectedMoodView(
                    mood: selectedMood,
                    layoutScale: metrics.selectedMoodScale,
                    isInteractionActive: isWheelDragging
                )
                .frame(maxWidth: 340)
                .padding(.horizontal, 28)
                .position(x: proxy.size.width / 2, y: metrics.selectedMoodCenterY)
                .zIndex(2)

                MoodDialWheel(selectedMood: $selectedMood, isDragging: $isWheelDragging, metrics: metrics)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityIdentifier("moodDial.surface")
                    .zIndex(1)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
