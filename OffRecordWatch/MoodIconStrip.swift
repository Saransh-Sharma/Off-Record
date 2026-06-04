import SwiftUI

struct MoodIconStrip: View {
    let selectedMood: WatchMoodValue
    let select: (WatchMoodValue) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(WatchMoodValue.dialOrder) { mood in
                    Button {
                        select(mood)
                    } label: {
                        WatchMoodSymbolMark(mood: mood, size: mood == selectedMood ? 30 : 24, showsSurface: false)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(mood == selectedMood ? mood.color.opacity(0.30) : WatchPalette.surface.opacity(0.50))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(mood == selectedMood ? mood.color.opacity(0.72) : WatchPalette.softBorder, lineWidth: 1)
                            }
                            .scaleEffect(mood == selectedMood ? 1.04 : 1)
                    }
                    .buttonStyle(WatchPressButtonStyle())
                    .accessibilityLabel(mood.displayName)
                    .accessibilityAddTraits(mood == selectedMood ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .frame(height: 44)
    }
}

struct WatchMoodSymbolMark: View {
    let mood: WatchMoodValue
    let size: CGFloat
    var showsSurface = true

    var body: some View {
        ZStack {
            if showsSurface {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [mood.color.opacity(0.92), mood.color.opacity(0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Image(systemName: mood.symbolName)
                .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(showsSurface ? mood.foregroundColor : mood.color)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
    }
}
