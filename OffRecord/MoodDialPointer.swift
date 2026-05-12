import SwiftUI

struct MoodDialPointer: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            MoodDialPointerShape()
                .fill(OffRecordColor.brandPlum)

            Circle()
                .fill(OffRecordColor.backgroundPrimary)
                .frame(width: 9, height: 9)
                .offset(x: 19.5, y: 77.5)
        }
        .frame(width: 48, height: 108)
        .accessibilityHidden(true)
    }
}
