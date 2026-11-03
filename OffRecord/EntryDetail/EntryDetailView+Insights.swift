//
//  EntryDetailView+Insights.swift
//  OffRecord
//
//  From Friday: the collapsible notes on this entry (mood, tone, what it is
//  about, recurring topics, and a line from Friday), read fresh on each open.
//

import SwiftUI

extension EntryDetailView {
    // MARK: - AI Insights Section

    var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withOffRecordAnimation(OffRecordMotion.snappy) {
                    showAIInsights.toggle()
                    if showAIInsights {
                        // Read fresh each time it opens, so an edit never shows stale notes.
                        aiAnalysis = EntryInsightAnalyzer.analyze(
                            text: text,
                            responseMode: entryResponseMode,
                            recurringTopic: recurringTopicName(for:)
                        )
                    }
                }
            }) {
                HStack(spacing: OffRecordSpacing.md) {
                    OffRecordIconBubble(
                        systemImage: "sparkles",
                        tint: OffRecordColor.textLavender,
                        fill: OffRecordColor.surfaceLavender,
                        size: 44,
                        iconSize: 17
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("From Friday", comment: "Header for the assistant’s notes on this entry. Friday is the assistant’s name, not the weekday.")
                            .font(OffRecordTypography.labelMedium)
                            .foregroundColor(OffRecordColor.textHeading)
                    }
                    .layoutPriority(1)

                    Image(systemName: showAIInsights ? "chevron.down" : "chevron.right")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .padding(18)
                .background(OffRecordColor.surfacePrimary, in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                        .stroke(OffRecordColor.borderSoft, lineWidth: 1)
                )
                .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            
            if showAIInsights, let analysis = aiAnalysis {
                VStack(alignment: .leading, spacing: 16) {
                    // Emotion & Sentiment
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            MiniMoodIcon(
                                mood: analysis.dominantEmotion.representativeMood,
                                size: 24,
                                opacity: 0.92
                            )
                            Text(analysis.dominantEmotion.representativeMood.displayName)
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                        .frame(width: 70)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tone")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(OffRecordColor.borderSoft)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(analysis.sentiment > 0 ? OffRecordColor.brandMint : OffRecordColor.brandPeach)
                                        .frame(width: geo.size.width * CGFloat(abs(analysis.sentiment)))
                                }
                            }
                            .frame(height: 8)
                            .accessibilityElement()
                            .accessibilityLabel("Tone")
                            .accessibilityValue(toneLabel(for: analysis.sentiment))

                            Text(toneLabel(for: analysis.sentiment))
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                    }
                    
                    Divider()
                    
                    // Intent
                    HStack {
                        Image(systemName: "quote.bubble")
                            .foregroundColor(OffRecordColor.textSky)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("About")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                            Text(analysis.intent.description)
                                .font(OffRecordTypography.bodySmall)
                                .foregroundColor(OffRecordColor.textPrimary)
                        }
                    }
                    
                    // Topics
                    if !analysis.topics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topics")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                            
                            FlowLayout(spacing: 6) {
                                ForEach(analysis.topics.prefix(5), id: \.self) { topic in
                                    Text(topic)
                                        .font(OffRecordTypography.metadata)
                                        .foregroundColor(OffRecordColor.textLavender)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(OffRecordColor.backgroundLavenderTint)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    // AI Response
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(OffRecordTypography.metadata)
                            Text("Friday", comment: "Name of the in-app assistant, not the weekday.")
                                .font(OffRecordTypography.metadata)
                        }
                        .foregroundColor(OffRecordColor.textSecondary)
                        Text(analysis.fridayLine)
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .italic()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OffRecordColor.surfaceLavender)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfaceWarm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 8)
    }

    /// The name Friday uses for `topic` when it comes up often, honoring Forget and Rename.
    private func recurringTopicName(for topic: String) -> String? {
        guard let node = FridayAssistantEngine.shared.knowledgeGraph.nodes[topic.lowercased()],
              node.type == .topic || node.type == .place,
              node.mentions > 3 else { return nil }
        let preferences = FridayMemoryPreferences.shared
        guard !preferences.isForgotten(node) else { return nil }
        return preferences.displayName(for: node)
    }

    private func toneLabel(for sentiment: Double) -> String {
        if sentiment > 0.2 {
            return String(localized: "Light", comment: "Tone of an entry: mostly positive.")
        }
        if sentiment < -0.2 {
            return String(localized: "Heavy", comment: "Tone of an entry: mostly negative.")
        }
        return String(localized: "Neutral", comment: "Tone of an entry: neither positive nor negative.")
    }
}
