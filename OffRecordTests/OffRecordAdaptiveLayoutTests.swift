import SwiftUI
import Testing
@testable import OffRecord

struct OffRecordAdaptiveLayoutTests {
    @Test func compactSizeClassAlwaysUsesCompactMode() {
        #expect(
            OffRecordAdaptiveLayoutMode.mode(
                forWidth: 820,
                horizontalSizeClass: .compact
            ) == .compact
        )
    }

    @Test func widthThresholdsPromoteRegularExpandedAndDesktopLikeModes() {
        #expect(OffRecordAdaptiveLayoutMode.mode(forWidth: 699) == .compact)
        #expect(OffRecordAdaptiveLayoutMode.mode(forWidth: 700) == .regular)
        #expect(OffRecordAdaptiveLayoutMode.mode(forWidth: 1024) == .expanded)
        #expect(OffRecordAdaptiveLayoutMode.mode(forWidth: 1366) == .desktopLike)
    }

    @Test func compactMetricsPreserveUncappedPhoneContent() {
        let metrics = OffRecordAdaptiveMetrics(width: 390, horizontalSizeClass: .compact)

        #expect(metrics.mode == .compact)
        #expect(metrics.readableContentMaxWidth == nil)
        #expect(metrics.pageMaxWidth == nil)
        #expect(metrics.pageHorizontalPadding == OffRecordSpacing.screenX)
    }

    @Test func regularMetricsCapReadableContentAndUseTwoColumnSettings() {
        let metrics = OffRecordAdaptiveMetrics(width: 900, horizontalSizeClass: .regular)

        #expect(metrics.mode == .regular)
        #expect(metrics.readableContentMaxWidth == 760)
        #expect(metrics.settingsColumns(dynamicTypeSize: .large).count == 2)
        #expect(metrics.settingsColumns(dynamicTypeSize: .accessibility1).count == 1)
    }
}
