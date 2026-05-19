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

private struct OffRecordClearGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let fallbackFill: Color
    let clearFill: Color
    let dimmingOpacity: Double
    let stroke: Color
    let lineWidth: CGFloat
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(fallbackFill.opacity(0.97))
                        .overlay {
                            shape.stroke(stroke.opacity(0.9), lineWidth: lineWidth)
                        }
                } else if #available(iOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.clear, in: shape)
                        .overlay {
                            shape.fill(clearFill)
                        }
                        .overlay {
                            shape.fill(Color.black.opacity(dimmingOpacity))
                        }
                        .overlay {
                            shape.stroke(stroke, lineWidth: lineWidth)
                        }
                        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(clearFill)
                        }
                        .overlay {
                            shape.fill(Color.black.opacity(dimmingOpacity * 0.8))
                        }
                        .overlay {
                            shape.stroke(stroke, lineWidth: lineWidth)
                        }
                        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
                }
            }
    }
}

extension View {
    func offRecordClearGlassSurface<S: Shape>(
        in shape: S,
        fallbackFill: Color = OffRecordColor.surfacePrimary,
        clearFill: Color = OffRecordColor.surfacePrimary.opacity(0.22),
        dimmingOpacity: Double = 0.055,
        stroke: Color = Color.white.opacity(0.58),
        lineWidth: CGFloat = 1,
        shadowColor: Color = OffRecordShadow.floatingColor,
        shadowRadius: CGFloat = 24,
        shadowY: CGFloat = 10
    ) -> some View {
        modifier(
            OffRecordClearGlassModifier(
                shape: shape,
                fallbackFill: fallbackFill,
                clearFill: clearFill,
                dimmingOpacity: dimmingOpacity,
                stroke: stroke,
                lineWidth: lineWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func offRecordClearGlassControl<S: Shape>(
        in shape: S,
        fallbackFill: Color = OffRecordColor.surfaceWarm,
        clearFill: Color = OffRecordColor.surfacePrimary.opacity(0.18),
        stroke: Color = Color.white.opacity(0.54)
    ) -> some View {
        offRecordClearGlassSurface(
            in: shape,
            fallbackFill: fallbackFill,
            clearFill: clearFill,
            dimmingOpacity: 0.045,
            stroke: stroke,
            shadowColor: Color.black.opacity(0.07),
            shadowRadius: 14,
            shadowY: 6
        )
    }

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
