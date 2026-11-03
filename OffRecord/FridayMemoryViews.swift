//
//  FridayMemoryViews.swift
//  OffRecord
//
//  "What Friday remembers": the people, places, themes, goals, and worries
//  Friday has picked up from the journal. Each row opens a page
//  (KnowledgePageView) with its entries and controls to rename the item or
//  ask Friday to forget it. KnowledgeGraphKit has no delete API and
//  re-learns names from new entries, so forgetting is a local suppression
//  list and renaming is a local alias map — both applied wherever Friday
//  shows or talks about her world. Stored on device only.
//

import SwiftUI

// MARK: - Preferences

@MainActor
final class FridayMemoryPreferences: ObservableObject {
    static let shared = FridayMemoryPreferences()

    private struct Stored: Codable {
        var forgottenIDs: Set<String> = []
        var aliases: [String: String] = [:]
    }

    @Published private(set) var forgottenIDs: Set<String> = []
    @Published private(set) var aliases: [String: String] = [:]

    private let file = FridayProtectedJSONFile<Stored>(fileName: "friday-memory-preferences.json")
    private let isEphemeral = ProcessInfo.processInfo.arguments.contains("-UITesting")

    private init() {
        guard !isEphemeral, let stored = file.load() else { return }
        forgottenIDs = stored.forgottenIDs
        aliases = stored.aliases
    }

    func isForgotten(_ node: PersonalKnowledgeGraph.KnowledgeNode) -> Bool {
        forgottenIDs.contains(node.id)
    }

    /// True when a free-text label (e.g. an emotional trigger topic) names something forgotten.
    func isForgottenLabel(_ label: String) -> Bool {
        let key = label.lowercased()
        return forgottenIDs.contains { id in
            id == key || id.hasSuffix(":\(key)")
        }
    }

    func displayName(for node: PersonalKnowledgeGraph.KnowledgeNode) -> String {
        if let alias = aliases[node.id], !alias.isEmpty { return alias }
        return node.label
    }

    func forget(_ node: PersonalKnowledgeGraph.KnowledgeNode) {
        forgottenIDs.insert(node.id)
        persist()
    }

    func restoreAll() {
        forgottenIDs.removeAll()
        persist()
    }

    /// Clears every forget and rename and deletes the file. Used when Friday is turned off.
    func reset() {
        forgottenIDs.removeAll()
        aliases.removeAll()
        file.delete()
    }

    func rename(_ node: PersonalKnowledgeGraph.KnowledgeNode, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == node.label {
            aliases.removeValue(forKey: node.id)
        } else {
            aliases[node.id] = String(trimmed.prefix(60))
        }
        persist()
    }

    private func persist() {
        guard !isEphemeral else { return }
        file.save(Stored(forgottenIDs: forgottenIDs, aliases: aliases))
    }
}

extension PersonalKnowledgeGraph {
    /// Top nodes as Friday should present them: forgotten items removed and
    /// renamed items relabeled.
    @MainActor
    func fridayVisibleNodes(
        ofType type: KnowledgeNode.NodeType? = nil,
        limit: Int = 10,
        preferences: FridayMemoryPreferences? = nil
    ) -> [KnowledgeNode] {
        let preferences = preferences ?? .shared
        let candidates = type == nil ? Array(nodes.values) : nodes.values.filter { $0.type == type }
        return candidates
            .filter { !preferences.isForgotten($0) }
            .sorted { $0.importance > $1.importance }
            .prefix(limit)
            .map { node in
                var copy = node
                copy.label = preferences.displayName(for: node)
                return copy
            }
    }
}

// MARK: - Presentation helpers

enum FridayMemoryTone {
    static func sentimentLabel(_ sentiment: Double) -> String {
        if sentiment > 0.3 { return String(localized: "Mostly positive", comment: "Overall feeling of entries that mention a remembered person, place, or topic") }
        if sentiment > 0.1 { return String(localized: "Leans positive", comment: "Overall feeling of entries that mention a remembered person, place, or topic") }
        if sentiment > -0.1 { return String(localized: "Mixed", comment: "Overall feeling of entries that mention a remembered person, place, or topic") }
        if sentiment > -0.3 { return String(localized: "Leans heavy", comment: "Overall feeling of entries that mention a remembered person, place, or topic") }
        return String(localized: "Mostly heavy", comment: "Overall feeling of entries that mention a remembered person, place, or topic")
    }

    static func sentimentFill(_ sentiment: Double) -> Color {
        if sentiment > 0.3 { return OffRecordColor.brandMint }
        if sentiment > 0.1 { return OffRecordColor.brandAqua }
        if sentiment > -0.1 { return OffRecordColor.textTertiary }
        if sentiment > -0.3 { return OffRecordColor.brandPeach }
        return OffRecordColor.brandCoral
    }

    static func sentimentText(_ sentiment: Double) -> Color {
        if sentiment > 0.3 { return OffRecordColor.textMint }
        if sentiment > 0.1 { return OffRecordColor.textAqua }
        if sentiment > -0.1 { return OffRecordColor.textSecondary }
        if sentiment > -0.3 { return OffRecordColor.textPeach }
        return OffRecordColor.textCoral
    }

    static func importanceLabel(_ importance: Double) -> String {
        if importance >= 0.66 { return String(localized: "Comes up a lot") }
        if importance >= 0.33 { return String(localized: "Comes up sometimes") }
        return String(localized: "Comes up rarely")
    }

    static func typeNoun(_ type: PersonalKnowledgeGraph.KnowledgeNode.NodeType) -> String {
        switch type {
        case .person: return String(localized: "person", comment: "Kind of thing Friday remembers, lowercase noun")
        case .place: return String(localized: "place", comment: "Kind of thing Friday remembers, lowercase noun")
        case .topic: return String(localized: "topic", comment: "Kind of thing Friday remembers, lowercase noun")
        case .goal: return String(localized: "goal", comment: "Kind of thing Friday remembers, lowercase noun")
        case .fear: return String(localized: "worry", comment: "Kind of thing Friday remembers, lowercase noun")
        case .activity: return String(localized: "activity", comment: "Kind of thing Friday remembers, lowercase noun")
        case .value: return String(localized: "value", comment: "Kind of thing Friday remembers, lowercase noun")
        case .event: return String(localized: "event", comment: "Kind of thing Friday remembers, lowercase noun")
        }
    }

    static func icon(_ type: PersonalKnowledgeGraph.KnowledgeNode.NodeType) -> String {
        switch type {
        case .person: return "person.fill"
        case .place: return "mappin.circle.fill"
        case .topic: return "tag.fill"
        case .goal: return "star.fill"
        case .fear: return "cloud.rain.fill"
        case .activity: return "figure.walk"
        case .value: return "heart.fill"
        case .event: return "calendar"
        }
    }
}

// MARK: - Importance bar

struct FridayImportanceBar: View {
    let importance: Double
    var showsLabel = true

    private var clamped: Double { max(0, min(1, importance)) }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            if showsLabel {
                HStack {
                    Text("Importance")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                    Spacer(minLength: OffRecordSpacing.sm)
                    Text(FridayMemoryTone.importanceLabel(clamped))
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textLavender)
                }
            }

            Capsule()
                .fill(OffRecordColor.textTertiary.opacity(0.2))
                .frame(height: showsLabel ? 8 : 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(OffRecordColor.brandLavenderDark)
                            .frame(width: max(6, geo.size.width * clamped))
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Importance")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent, \(FridayMemoryTone.importanceLabel(clamped))")
    }
}

// MARK: - Row

struct FridayMemoryRow: View {
    let node: PersonalKnowledgeGraph.KnowledgeNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OffRecordSpacing.md) {
                Circle()
                    .fill(FridayMemoryTone.sentimentFill(node.sentimentAssociation))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                    Text(node.label)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(mentionText) · \(FridayMemoryTone.sentimentLabel(node.sentimentAssociation).lowercased())")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }

                Spacer(minLength: OffRecordSpacing.sm)

                FridayImportanceBar(importance: node.importance, showsLabel: false)
                    .frame(width: 48)

                Image(systemName: "chevron.right")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.label)
        .accessibilityValue("\(mentionText), \(FridayMemoryTone.sentimentLabel(node.sentimentAssociation)), importance \(Int((max(0, min(1, node.importance)) * 100).rounded())) percent")
        .accessibilityHint("Shows details and options.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("friday.memoryRow.\(node.id)")
    }

    private var mentionText: String {
        String(AttributedString(localized: "^[\(node.mentions) mention](inflect: true)").characters)
    }
}
