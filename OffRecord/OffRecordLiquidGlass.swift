//
//  OffRecordLiquidGlass.swift
//  OffRecord
//
//  Shared Liquid Glass compatibility helpers for post-onboarding UI.
//

import SwiftUI

extension Color {
    static var offRecordReadableTintedForeground: Color {
        OffRecordReadableTintStyle.brand.foreground
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
        fallbackFill: Color = OffRecordColor.surfaceWarm,
        border: Color? = nil
    ) -> some View {
        if #available(iOS 26.0, *) {
            background(fallbackFill.opacity(0.92), in: shape)
                .glassEffect(.regular.tint(tint).interactive(), in: shape)
                .overlay(
                    shape.stroke((border ?? tint ?? OffRecordColor.borderSoft).opacity(border == nil ? 0.35 : 1), lineWidth: 1)
                )
        } else {
            background(fallbackFill, in: shape)
                .overlay(
                    shape.stroke((border ?? tint ?? OffRecordColor.borderSoft).opacity(border == nil ? 0.35 : 1), lineWidth: 1)
                )
        }
    }

    func offRecordReadableGlassControl<S: Shape>(
        _ style: OffRecordReadableTintStyle,
        in shape: S
    ) -> some View {
        foregroundStyle(style.foreground)
            .offRecordGlassControl(
                tint: style.tint,
                in: shape,
                fallbackFill: style.fill,
                border: style.border
            )
    }

    @ViewBuilder
    func offRecordGlassBar(
        cornerRadius: CGFloat = 28,
        fallbackFill: Color = OffRecordColor.surfacePrimary
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            background(fallbackFill.opacity(0.96), in: shape)
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(OffRecordColor.borderSoft, lineWidth: 1))
                .shadow(color: OffRecordShadow.floatingColor, radius: 24, x: 0, y: 10)
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
