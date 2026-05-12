import SwiftUI

struct MoodDialPointer: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            MoodDialPointerShape()
                .fill(OffRecordColor.brandPlum)

            Circle()
                .fill(OffRecordColor.backgroundPrimary)
                .frame(width: 9.5, height: 9.5)
                .offset(x: 20.25, y: 101.25)
        }
        .frame(width: 50, height: 136)
        .accessibilityHidden(true)
    }
}
