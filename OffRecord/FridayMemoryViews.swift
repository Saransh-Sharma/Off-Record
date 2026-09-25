//
//  FridayMemoryViews.swift
//  OffRecord
//
//  "What Friday remembers": the people, places, themes, goals, and worries
//  Friday has picked up from the journal, with local controls to rename an
//  item or ask Friday to forget it. KnowledgeGraphKit has no delete API and
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
        if sentiment > 0.3 { return "Mostly warm" }
        if sentiment > 0.1 { return "Leans positive" }
        if sentiment > -0.1 { return "Mixed or neutral" }
        if sentiment > -0.3 { return "Leans heavy" }
        return "Often heavy"
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
        if importance >= 0.66 { return "On your mind a lot" }
        if importance >= 0.33 { return "Comes up sometimes" }
        return "Now and then"
    }

    static func typeNoun(_ type: PersonalKnowledgeGraph.KnowledgeNode.NodeType) -> String {
        switch type {
        case .person: return "person"
        case .place: return "place"
        case .topic: return "theme"
        case .goal: return "goal"
        case .fear: return "worry"
        case .activity: return "activity"
        case .value: return "value"
        case .event: return "event"
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
        .accessibilityHint("Shows details and options")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("friday.memoryRow.\(node.id)")
    }

    private var mentionText: String {
        node.mentions == 1 ? "1 mention" : "\(node.mentions) mentions"
    }
}

// MARK: - Detail sheet

struct FridayMemoryDetailSheet: View {
    /// The raw graph node; `label` is the name as written in the journal.
    let node: PersonalKnowledgeGraph.KnowledgeNode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = FridayMemoryPreferences.shared
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingForget = false
    @State private var forgetTrigger = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffRecordSpacing.xl) {
                    header
                    stats
                    FridayImportanceBar(importance: node.importance)
                        .padding(OffRecordSpacing.lg)
                        .offRecordCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm, shadow: false)
                    actions
                    privacyNote
                }
                .padding(.horizontal, OffRecordSpacing.xxl)
                .padding(.vertical, OffRecordSpacing.lg)
            }
            .background(OffRecordAppBackground().ignoresSafeArea())
            .navigationTitle(preferences.displayName(for: node))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename \(FridayMemoryTone.typeNoun(node.type))", isPresented: $isRenaming) {
                TextField("Name", text: $renameText)
                Button("Save") { preferences.rename(node, to: renameText) }
                if preferences.aliases[node.id] != nil {
                    Button("Use original name") { preferences.rename(node, to: node.label) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Friday will use this name when she talks about it. Your entries stay as you wrote them.")
            }
            .confirmationDialog(
                "Forget \(preferences.displayName(for: node))?",
                isPresented: $isConfirmingForget,
                titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    forgetTrigger += 1
                    preferences.forget(node)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Friday will stop showing or mentioning this. Your journal entries aren’t changed, and you can restore it later from My World.")
            }
            .sensoryFeedback(.success, trigger: forgetTrigger)
        }
    }

    private var header: some View {
        HStack(spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(
                systemImage: FridayMemoryTone.icon(node.type),
                tint: OffRecordColor.textLavender,
                fill: OffRecordColor.backgroundLavenderTint,
                size: 48,
                iconSize: 20
            )
            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text(preferences.displayName(for: node))
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
                Text(subtitle)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let noun = FridayMemoryTone.typeNoun(node.type).capitalized
        if preferences.aliases[node.id] != nil {
            return "\(noun) · written as “\(node.label)”"
        }
        return noun
    }

    private var stats: some View {
        HStack(spacing: OffRecordSpacing.md) {
            statTile(
                value: "\(node.mentions)",
                label: node.mentions == 1 ? "Mention" : "Mentions",
                valueColor: OffRecordColor.textLavender
            )
            statTile(
                value: FridayMemoryTone.sentimentLabel(node.sentimentAssociation),
                label: "How it feels",
                valueColor: FridayMemoryTone.sentimentText(node.sentimentAssociation)
            )
            statTile(
                value: node.lastSeen.formatted(.dateTime.month(.abbreviated).day()),
                label: "Last mentioned",
                valueColor: OffRecordColor.textPrimary
            )
        }
    }

    private func statTile(value: String, label: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            Text(value)
                .font(OffRecordTypography.labelLarge)
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(OffRecordTypography.annotation)
                .foregroundStyle(OffRecordColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OffRecordSpacing.md)
        .offRecordCard(cornerRadius: OffRecordRadius.md, fill: OffRecordColor.surfaceWarm, shadow: false)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: OffRecordSpacing.sm) {
            Button {
                dismiss()
                OffRecordNavigationRouter.shared.route(.timeline(query: node.label), canNavigate: true)
            } label: {
                Label("See entries", systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandLavenderDark))
            .accessibilityHint("Searches your timeline for \(node.label)")
            .accessibilityIdentifier("friday.memory.seeEntries")

            HStack(spacing: OffRecordSpacing.sm) {
                Button {
                    renameText = preferences.displayName(for: node)
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))
                .accessibilityIdentifier("friday.memory.rename")

                Button {
                    isConfirmingForget = true
                } label: {
                    Label("Forget", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textCoral, fill: OffRecordColor.surfacePrimary))
                .accessibilityHint("Hides this from Friday. Your entries aren’t changed.")
                .accessibilityIdentifier("friday.memory.forget")
            }
        }
    }

    private var privacyNote: some View {
        Label("Names and choices here stay on this device.", systemImage: "lock.shield.fill")
            .font(OffRecordTypography.metadata)
            .foregroundStyle(OffRecordColor.textSage)
    }
}
