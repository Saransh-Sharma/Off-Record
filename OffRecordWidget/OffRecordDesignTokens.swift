//
//  OffRecordDesignTokens.swift
//  OffRecordWidget
//
//  Widget-only tokens: the widget background and typography. Colors come
//  from OffRecordSystemShared/OffRecordColor.swift, shared with the app.
//

import SwiftUI
import UIKit
import WidgetKit

// MARK: - Widget-Only Modifiers

struct OffRecordWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            OffRecordColor.appBackgroundGradient
        }
    }
}

extension View {
    func offRecordWidgetBackground() -> some View {
        modifier(OffRecordWidgetBackground())
    }
}

enum OffRecordWidgetTypography {
    static let titleLarge = Font.system(.title, design: .rounded, weight: .bold)
    static let titleMedium = Font.system(.title2, design: .rounded, weight: .bold)
    static let titleSmall = Font.system(.title3, design: .rounded, weight: .bold)
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.callout, design: .default, weight: .regular)
    static let bodySmall = Font.system(.subheadline, design: .default, weight: .regular)
    static let label = Font.system(.footnote, design: .default, weight: .semibold)
    static let eyebrow = Font.system(.caption, design: .rounded, weight: .semibold)
    static let metadata = Font.system(.caption, design: .default, weight: .regular)
    static let micro = Font.system(.caption2, design: .default, weight: .medium)
    static let numberLarge = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let numberMedium = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let numberSmall = Font.system(.headline, design: .rounded, weight: .semibold).monospacedDigit()
}
