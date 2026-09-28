//
//  MilestoneCelebrationView.swift
//  OffRecord
//
//  Streak milestone overlay (7, 14, 30, 50, 100, 200, 365 days; see
//  `GoalManager.milestones`). Plays a short Canvas confetti burst with a
//  success haptic; with Reduce Motion it is a static badge that fades in.
//

import SwiftUI

struct MilestoneCelebrationView: View {
    let days: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrate = false
    @State private var badgeVisible = false
    @State private var showsConfetti = true
    @State private var burstStart = Date()

    var body: some View {
        ZStack {
            OffRecordColor.darkBackground.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            if !reduceMotion && showsConfetti {
                ConfettiBurstView(start: burstStart)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            card
        }
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            burstStart = Date()
            celebrate = true
            withOffRecordAnimation(OffRecordMotion.bouncy) {
                badgeVisible = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(ConfettiBurstView.duration + 0.2))
            showsConfetti = false
        }
    }

    private var card: some View {
        VStack(spacing: OffRecordSpacing.lg) {
            badge

            Text("\(days) Days in a Row")
                .font(OffRecordTypography.titleLarge)
                .foregroundStyle(OffRecordColor.textHeading)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Button(action: onDismiss) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .offRecordPillButton()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("insights.milestone.dismiss")
        }
        .padding(OffRecordSpacing.xxxl)
        .frame(maxWidth: 380)
        .offRecordGlassBar(cornerRadius: OffRecordRadius.xl, fallbackFill: OffRecordColor.surfaceWarm)
        .offRecordShadow(.floating)
        .padding(OffRecordSpacing.xxl)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(OffRecordColor.surfacePeach)
            Circle()
                .stroke(OffRecordColor.brandYellow, lineWidth: 3)
                .padding(OffRecordSpacing.xs)
            Image(systemName: "trophy.fill")
                .font(OffRecordTypography.numberLarge)
                .foregroundStyle(OffRecordColor.textYellow)
        }
        .frame(width: 96, height: 96)
        .scaleEffect(reduceMotion || badgeVisible ? 1 : 0.55)
        .opacity(badgeVisible ? 1 : 0)
        .accessibilityHidden(true)
    }
}

/// A one-shot confetti burst drawn with Canvas. Purely decorative.
struct ConfettiBurstView: View {
    static let duration: TimeInterval = 2.6

    let start: Date
    @State private var particles = ConfettiParticle.burst(count: 72)

    private static let palette: [Color] = [
        OffRecordColor.brandPeach,
        OffRecordColor.brandYellow,
        OffRecordColor.brandMint,
        OffRecordColor.brandAqua,
        OffRecordColor.brandLavender,
        OffRecordColor.brandBlush,
        OffRecordColor.brandCoral
    ]

    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed >= 0, elapsed <= Self.duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.4)
                let gravity: Double = 900
                let fade = max(0, min(1, (Self.duration - elapsed) / 0.8))

                for particle in particles {
                    let t = elapsed
                    let x = origin.x + particle.velocity.dx * t
                    let y = origin.y + particle.velocity.dy * t + 0.5 * gravity * t * t
                    var particleContext = context
                    particleContext.opacity = fade
                    particleContext.translateBy(x: x, y: y)
                    particleContext.rotate(by: .radians(particle.spin * t))
                    let rect = CGRect(
                        x: -particle.size.width / 2,
                        y: -particle.size.height / 2,
                        width: particle.size.width,
                        height: particle.size.height
                    )
                    let path = particle.isRound
                        ? Path(ellipseIn: rect)
                        : Path(roundedRect: rect, cornerRadius: 1.5)
                    particleContext.fill(path, with: .color(Self.palette[particle.colorIndex % Self.palette.count]))
                }
            }
        }
    }
}

struct ConfettiParticle {
    let velocity: CGVector
    let size: CGSize
    let spin: Double
    let colorIndex: Int
    let isRound: Bool

    static func burst(count: Int) -> [ConfettiParticle] {
        (0..<count).map { index in
            // Fan upward between roughly 200° and 340° so pieces arc out and fall.
            let angle = Double.random(in: (1.1 * .pi)...(1.9 * .pi))
            let speed = Double.random(in: 320...720)
            let width = CGFloat.random(in: 6...10)
            return ConfettiParticle(
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: CGSize(width: width, height: width * CGFloat.random(in: 0.5...1.4)),
                spin: Double.random(in: -9...9),
                colorIndex: index,
                isRound: index % 3 == 0
            )
        }
    }
}

#Preview {
    MilestoneCelebrationView(days: 30) {}
}
