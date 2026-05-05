//
//  OffRecordLiquidGlass.swift
//  OffRecord
//
//  Shared Liquid Glass compatibility helpers for post-onboarding UI.
//

import SwiftUI

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
        fallbackFill: Color = Color(.secondarySystemGroupedBackground)
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(fallbackFill, in: shape)
        }
    }

    @ViewBuilder
    func offRecordGlassBar(
        cornerRadius: CGFloat = 28,
        fallbackFill: Color = Color(.systemGroupedBackground)
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(fallbackFill, in: shape)
        }
    }

    func offRecordContentCard(
        cornerRadius: CGFloat = 16,
        fill: Color = Color(.secondarySystemGroupedBackground)
    ) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
