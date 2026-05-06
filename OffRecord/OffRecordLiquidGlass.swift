//
//  OffRecordLiquidGlass.swift
//  OffRecord
//
//  Shared Liquid Glass compatibility helpers for post-onboarding UI.
//

import SwiftUI

extension Color {
    static var offRecordReadableTintedForeground: Color {
        OffRecordColor.textBrand
    }
}

struct OffRecordGlassControlGroup<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func offRecordGlassControl<S: Shape>(
        tint: Color? = nil,
        in shape: S,
        fallbackFill: Color = OffRecordColor.surfaceWarm
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(fallbackFill, in: shape)
                .overlay(shape.stroke((tint ?? OffRecordColor.borderSoft).opacity(0.35), lineWidth: 1))
        }
    }

    @ViewBuilder
    func offRecordGlassBar(
        cornerRadius: CGFloat = 28,
        fallbackFill: Color = OffRecordColor.surfacePrimary
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(fallbackFill, in: shape)
                .overlay(shape.stroke(OffRecordColor.borderSoft, lineWidth: 1))
                .shadow(color: OffRecordShadow.floatingColor, radius: 24, x: 0, y: 10)
        }
    }

    func offRecordContentCard(
        cornerRadius: CGFloat = OffRecordRadius.xl,
        fill: Color = OffRecordColor.surfacePrimary
    ) -> some View {
        offRecordCard(cornerRadius: cornerRadius, fill: fill)
    }
}
