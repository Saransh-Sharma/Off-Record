//
//  OffRecordAdaptiveLayout.swift
//  OffRecord
//
//  Shared width-driven layout metrics for iPhone-first adaptation.
//

import SwiftUI

enum OffRecordAdaptiveLayoutMode: Int, Comparable {
    case compact
    case regular
    case expanded
    case desktopLike

    static func < (lhs: OffRecordAdaptiveLayoutMode, rhs: OffRecordAdaptiveLayoutMode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func mode(
        forWidth width: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass? = nil
    ) -> OffRecordAdaptiveLayoutMode {
        if horizontalSizeClass == .compact {
            return .compact
        }

        switch width {
        case ..<700:
            return .compact
        case ..<1024:
            return .regular
        case ..<1366:
            return .expanded
        default:
            return .desktopLike
        }
    }

    var usesCompactPhoneChrome: Bool {
        self == .compact
    }

    var supportsSupplementaryPanels: Bool {
        self >= .expanded
    }
}

struct OffRecordAdaptiveMetrics {
    let width: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?
    let mode: OffRecordAdaptiveLayoutMode

    init(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass? = nil) {
        self.width = width
        self.horizontalSizeClass = horizontalSizeClass
        self.mode = OffRecordAdaptiveLayoutMode.mode(
            forWidth: width,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    var pageHorizontalPadding: CGFloat {
        switch mode {
        case .compact:
            return OffRecordSpacing.screenX
        case .regular:
            return 28
        case .expanded:
            return 32
        case .desktopLike:
            return 40
        }
    }

    var readableContentMaxWidth: CGFloat? {
        switch mode {
        case .compact:
            return nil
        case .regular:
            return 760
        case .expanded:
            return 900
        case .desktopLike:
            return 960
        }
    }

    var pageMaxWidth: CGFloat? {
        switch mode {
        case .compact:
            return nil
        case .regular:
            return 860
        case .expanded:
            return 1180
        case .desktopLike:
            return 1240
        }
    }

    var timelineListWidth: CGFloat {
        switch mode {
        case .compact, .regular:
            return min(width, 760)
        case .expanded:
            return min(max(width * 0.44, 430), 560)
        case .desktopLike:
            return min(max(width * 0.38, 460), 620)
        }
    }

    var todayCapturePanelWidth: CGFloat {
        switch mode {
        case .compact:
            return width
        case .regular:
            return 560
        case .expanded:
            return 360
        case .desktopLike:
            return 390
        }
    }

    var fridayReadableWidth: CGFloat {
        switch mode {
        case .compact:
            return width
        case .regular:
            return 720
        case .expanded:
            return 820
        case .desktopLike:
            return 860
        }
    }

    func settingsColumns(dynamicTypeSize: DynamicTypeSize) -> [GridItem] {
        guard mode >= .regular, !dynamicTypeSize.isAccessibilitySize else {
            return [GridItem(.flexible(), spacing: OffRecordSpacing.lg)]
        }

        return [
            GridItem(.flexible(), spacing: OffRecordSpacing.lg),
            GridItem(.flexible(), spacing: OffRecordSpacing.lg)
        ]
    }

    func insightsColumns(dynamicTypeSize: DynamicTypeSize) -> [GridItem] {
        guard mode >= .expanded, !dynamicTypeSize.isAccessibilitySize else {
            return [GridItem(.flexible(), spacing: OffRecordSpacing.lg)]
        }

        return [
            GridItem(.flexible(), spacing: OffRecordSpacing.lg),
            GridItem(.flexible(), spacing: OffRecordSpacing.lg)
        ]
    }
}

private struct OffRecordPointerLiftModifier: ViewModifier {
    let enabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(enabled && isHovering ? 1.012 : 1)
            .shadow(
                color: enabled && isHovering ? Color.black.opacity(0.08) : .clear,
                radius: enabled && isHovering ? 14 : 0,
                x: 0,
                y: enabled && isHovering ? 6 : 0
            )
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { hovering in
                guard enabled else { return }
                isHovering = hovering
            }
    }
}

extension View {
    func offRecordPointerLift(enabled: Bool = true) -> some View {
        modifier(OffRecordPointerLiftModifier(enabled: enabled))
    }
}
