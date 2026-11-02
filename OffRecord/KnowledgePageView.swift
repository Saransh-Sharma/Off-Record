//
//  KnowledgePageView.swift
//  OffRecord
//
//  A page for one person, place, or topic in Friday's My World: how often it
//  comes up by month, the mood of those entries, the first and last mention,
//  the entries themselves (each opens the entry), and Rename and Forget.
//  Entries kept out of Friday and high-risk entries never appear here, and a
//  forgotten item closes its page. See KnowledgeMentionAggregator.
//

import Charts
import CoreData
import SwiftUI

/// Pushes a page for a graph node by its ID, so the page follows the live graph.
struct KnowledgeNodeRoute: Hashable, Identifiable {
    let id: String
}

struct KnowledgePageView: View {
    let nodeID: String

    @ObservedObject private var assistant = FridayAssistantEngine.shared
    @ObservedObject private var preferences = FridayMemoryPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        predicate: DiaryEntry.startedEntryPredicate
    )
    private var entries: FetchedResults<DiaryEntry>

    @State private var content: KnowledgePageContent?
    @State private var openedEntry: DiaryEntry?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingForget = false
    @State private var forgetTrigger = 0
    @State private var hasClosed = false
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 140

    static let maximumListedEntries = 8

    private var node: PersonalKnowledgeGraph.KnowledgeNode? { assistant.knowledgeGraph.nodes[nodeID] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OffRecordSpacing.xl) {
                if let node, let content {
                    header(node: node, content: content)
                    stats(node: node, content: content)
                    if !content.summary.months.isEmpty {
                        overTimeCard(content: content)
                    }
                    if !content.summary.moods.isEmpty {
                        moodCard(content: content)
                    }
                    entriesCard(node: node, content: content)
                    actions(node: node, content: content)
                } else if node == nil {
                    ContentUnavailableView {
                        Label(String(localized: "Not Remembered", comment: "Title when a My World item no longer exists"), systemImage: "eye.slash")
                    } description: {
                        Text("I don’t remember this anymore.", comment: "Friday, when a My World item is gone")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, OffRecordSpacing.section)
                }
            }
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.lg)
            .frame(maxWidth: OffRecordLayout.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(OffRecordAppBackground().ignoresSafeArea())
        .navigationTitle(content?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refreshSignature) { refresh() }
        .navigationDestination(item: $openedEntry) { entry in
            EntryDetailView(entry: entry)
        }
        .alert(renameTitle, isPresented: $isRenaming) {
            TextField(String(localized: "Name"), text: $renameText)
            Button(String(localized: "Save")) {
                if let node { preferences.rename(node, to: renameText) }
            }
            if let node, preferences.aliases[node.id] != nil {
                Button(String(localized: "Reset Name")) { preferences.rename(node, to: node.label) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("I’ll use this name from now on. Your entries won’t change.")
        }
        .confirmationDialog(
            String(localized: "Forget \(content?.title ?? "")?", comment: "Confirmation title. The argument is a remembered name."),
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Forget"), role: .destructive) {
                guard let node else { return }
                forgetTrigger += 1
                preferences.forget(node)
                close()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("I’ll stop bringing this up. Your entries won’t change, and you can restore it in My World.")
        }
        .sensoryFeedback(.success, trigger: forgetTrigger)
    }

    // MARK: Data

    private var refreshSignature: String {
        let latest = entries.lazy.compactMap(\.updatedAt).max()?.timeIntervalSinceReferenceDate ?? 0
        let alias = preferences.aliases[nodeID] ?? ""
        return "\(nodeID)|\(node?.label ?? "")|\(entries.count)|\(latest)|\(alias)|\(preferences.forgottenIDs.contains(nodeID))"
    }

    private func refresh() {
        guard let node else {
            content = nil
            return
        }
        content = KnowledgeMentionAggregator.content(
            for: node,
            entries: Array(entries),
            isForgotten: preferences.isForgotten(node),
            alias: preferences.aliases[node.id]
        )
        if content == nil {
            // Forgotten: nothing about it is shown.
            close()
        }
    }

    private func close() {
        guard !hasClosed else { return }
        hasClosed = true
        dismiss()
    }

    // MARK: Sections

    private func header(node: PersonalKnowledgeGraph.KnowledgeNode, content: KnowledgePageContent) -> some View {
        HStack(spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(
                systemImage: FridayMemoryTone.icon(node.type),
                tint: OffRecordColor.textLavender,
                fill: OffRecordColor.backgroundLavenderTint,
                size: 52,
                iconSize: 22
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text(content.title)
                    .font(OffRecordTypography.titleMedium)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("friday.knowledgePage.title")
                Text(subtitle(node: node, content: content))
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Text(leadLine(content: content))
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OffRecordSpacing.xxs)
                    .accessibilityIdentifier("friday.knowledgePage.lead")
            }
        }
    }

    private func subtitle(node: PersonalKnowledgeGraph.KnowledgeNode, content: KnowledgePageContent) -> String {
        let noun = FridayMemoryTone.typeNoun(node.type).capitalized
        if let writtenAs = content.writtenAs {
            return String(localized: "\(noun) · written as “\(writtenAs)”", comment: "The first placeholder is a kind, like Person; the second is the name as written in the journal")
        }
        return noun
    }

    private func leadLine(content: KnowledgePageContent) -> String {
        let count = content.summary.entryCount
        guard count > 0 else {
            return String(localized: "No entries to show for \(content.title) yet.", comment: "My World page with no readable entries. The argument is a name.")
        }
        return String(AttributedString(localized: "You mentioned \(content.title) in ^[\(count) entry](inflect: true).", comment: "My World page lead. The first argument is a name.").characters)
    }

    private func stats(node: PersonalKnowledgeGraph.KnowledgeNode, content: KnowledgePageContent) -> some View {
        HStack(spacing: OffRecordSpacing.md) {
            if let first = content.summary.firstMention, let last = content.summary.lastMention {
                statTile(
                    value: first.formatted(.dateTime.month(.abbreviated).day().year()),
                    label: String(localized: "First Mentioned"),
                    valueColor: OffRecordColor.textPrimary,
                    identifier: "friday.knowledgePage.first"
                )
                statTile(
                    value: last.formatted(.dateTime.month(.abbreviated).day().year()),
                    label: String(localized: "Last Mentioned"),
                    valueColor: OffRecordColor.textPrimary,
                    identifier: "friday.knowledgePage.last"
                )
            }
            statTile(
                value: FridayMemoryTone.sentimentLabel(node.sentimentAssociation),
                label: String(localized: "Tone", comment: "Label for how positive or heavy the entries feel"),
                valueColor: FridayMemoryTone.sentimentText(node.sentimentAssociation),
                identifier: "friday.knowledgePage.tone"
            )
        }
    }

    private func statTile(value: String, label: String, valueColor: Color, identifier: String) -> some View {
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
        .accessibilityIdentifier(identifier)
    }

    private func overTimeCard(content: KnowledgePageContent) -> some View {
        let months = content.summary.months
        let maxCount = max(1, months.map(\.count).max() ?? 1)
        let summary = overTimeSummary(content: content)
        return VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: String(localized: "Over Time", comment: "Chart of mentions by month"), systemImage: "chart.bar.fill", tint: OffRecordColor.textLavender)
            InsightChartSummary(text: summary)

            Chart(months) { month in
                BarMark(
                    x: .value("Month", month.month, unit: .month),
                    y: .value("Entries", month.count),
                    width: .ratio(0.6)
                )
                .cornerRadius(OffRecordRadius.xs)
                .foregroundStyle(month.count > 0 ? AnyShapeStyle(Self.barFill) : AnyShapeStyle(OffRecordColor.textTertiary.opacity(0.2)))
                .accessibilityLabel(month.month.formatted(.dateTime.month(.wide).year()))
                .accessibilityValue(String(AttributedString(localized: "^[\(month.count) entry](inflect: true)").characters))
            }
            .chartYScale(domain: 0...(Double(maxCount) * 1.2))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: months.count > 6 ? 2 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(OffRecordTypography.annotation)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
            }
            .frame(height: chartHeight)
            .accessibilityChartDescriptor(KnowledgeMonthsAXDescriptor(months: months, summary: summary))
            .accessibilityIdentifier("friday.knowledgePage.chart")
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
    }

    private func overTimeSummary(content: KnowledgePageContent) -> String {
        let count = content.summary.entryCount
        if count < 3 {
            return String(AttributedString(localized: "Only ^[\(count) entry](inflect: true) so far.", comment: "Thin evidence on a My World page").characters)
        }
        guard let busiest = content.summary.busiestMonth else { return "" }
        return String(localized: "Most mentions were in \(busiest.month.formatted(.dateTime.month(.wide).year())).", comment: "My World chart summary. The argument is a month and year.")
    }

    private func moodCard(content: KnowledgePageContent) -> some View {
        let moods = content.summary.moods
        let total = moods.reduce(0) { $0 + $1.count }
        let top = moods.first
        return VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: String(localized: "Mood When Mentioned"), systemImage: "face.smiling", tint: OffRecordColor.textLavender)
            if let top {
                InsightChartSummary(text: String(localized: "\(top.mood.displayName) in \(top.count) of \(total) entries with a mood.", comment: "My World mood summary. The first argument is a mood name."))
            }
            VStack(spacing: OffRecordSpacing.sm) {
                ForEach(moods) { item in
                    HStack(spacing: OffRecordSpacing.sm) {
                        MiniMoodIcon(mood: item.mood, size: 22, opacity: 0.95)
                        Text(item.mood.displayName)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(item.mood.color.opacity(0.85))
                                .frame(width: max(6, geo.size.width * CGFloat(item.count) / CGFloat(max(1, top?.count ?? 1))))
                        }
                        .frame(height: 8)
                        Text("\(item.count)")
                            .font(OffRecordTypography.numberSmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.mood.displayName)
                    .accessibilityValue(String(AttributedString(localized: "^[\(item.count) entry](inflect: true)").characters))
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceWarm)
        .accessibilityIdentifier("friday.knowledgePage.moods")
    }

    private func entriesCard(node: PersonalKnowledgeGraph.KnowledgeNode, content: KnowledgePageContent) -> some View {
        let mentions = Array(content.summary.mentions.prefix(Self.maximumListedEntries))
        return VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            if !mentions.isEmpty {
                Text("Entries", comment: "Heading above the entries that mention a remembered name")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                    .accessibilityAddTraits(.isHeader)

                ForEach(mentions) { mention in
                    if let entry = entry(for: mention.entryID) {
                        Button {
                            openedEntry = entry
                        } label: {
                            FridayEvidenceChip(evidence: mention.evidence)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "Entry from \(FridayEvidenceChip.spokenDate(mention.date)). \(mention.snippet)", comment: "VoiceOver: an entry that mentions a remembered name"))
                        .accessibilityHint(String(localized: "Opens the entry."))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("friday.knowledgePage.entry")
                    }
                }
            }

            Button {
                OffRecordNavigationRouter.shared.route(.timeline(query: node.label), canNavigate: true)
            } label: {
                Label(String(localized: "Show in Timeline"), systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandLavenderDark))
            .accessibilityHint(String(localized: "Searches your timeline for \(node.label)."))
            .accessibilityIdentifier("friday.memory.seeEntries")
            .padding(.top, OffRecordSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friday.knowledgePage.entries")
    }

    private func actions(node: PersonalKnowledgeGraph.KnowledgeNode, content: KnowledgePageContent) -> some View {
        HStack(spacing: OffRecordSpacing.sm) {
            Button {
                renameText = content.title
                isRenaming = true
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))
            .accessibilityIdentifier("friday.memory.rename")

            Button {
                isConfirmingForget = true
            } label: {
                Label(String(localized: "Forget"), systemImage: "eye.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textCoral, fill: OffRecordColor.surfacePrimary))
            .accessibilityHint(String(localized: "Hides this from Friday."))
            .accessibilityIdentifier("friday.memory.forget")
        }
    }

    private var renameTitle: String {
        guard let node else { return String(localized: "Rename") }
        return String(localized: "Rename \(FridayMemoryTone.typeNoun(node.type).capitalized)")
    }

    private func entry(for id: UUID) -> DiaryEntry? {
        entries.first { $0.id == id }
    }

    static let barFill = LinearGradient(
        colors: [OffRecordColor.brandLavenderDark, OffRecordColor.brandLavender],
        startPoint: .top,
        endPoint: .bottom
    )
}

private struct KnowledgeMonthsAXDescriptor: AXChartDescriptorRepresentable {
    let months: [KnowledgeMonthCount]
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = months.map { $0.month.formatted(.dateTime.month(.wide).year()) }
        let maxCount = Double(max(1, months.map(\.count).max() ?? 1))
        return AXChartDescriptor(
            title: String(localized: "Over Time", comment: "Chart of mentions by month"),
            summary: summary,
            xAxis: AXCategoricalDataAxisDescriptor(title: String(localized: "Month", comment: "Chart axis title"), categoryOrder: names),
            yAxis: AXNumericDataAxisDescriptor(title: String(localized: "Entries", comment: "Chart axis title: number of journal entries"), range: 0...maxCount, gridlinePositions: []) { value in
                String(AttributedString(localized: "^[\(Int(value)) entry](inflect: true)").characters)
            },
            additionalAxes: [],
            series: [
                AXDataSeriesDescriptor(
                    name: String(localized: "Entries per month"),
                    isContinuous: false,
                    dataPoints: zip(names, months).map { name, month in
                        AXDataPoint(x: name, y: Double(month.count))
                    }
                )
            ]
        )
    }
}
