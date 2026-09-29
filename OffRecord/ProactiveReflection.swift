//
//  ProactiveReflection.swift
//  OffRecord
//
//  Local-only proactive reflection loop for Friday.
//  Derived coaching state is rebuildable from journal entries and never leaves device.
//

import CoreData
import Foundation
import os.log
import SwiftUI

private let proactiveReflectionLogger = Logger(subsystem: "com.singularity.offrecord", category: "ProactiveReflection")
private let proactiveReflectionReminderBodyKey = "offrecord_proactive_reflection_reminder_body"

// MARK: - App bridges

// The models and analyzer live in ReflectionKit; the app adds presentation and Core Data glue.

extension ReflectionInsight.Category {
    /// Raw values are persisted with saved insights; show this instead.
    var displayName: String {
        switch self {
        case .pattern: return String(localized: "Pattern", comment: "Insight category badge")
        case .decision: return String(localized: "Decision", comment: "Insight category badge")
        case .weekly: return String(localized: "Weekly", comment: "Insight category badge")
        case .prompt: return String(localized: "Prompt", comment: "Insight category badge")
        }
    }
}

extension ReflectionEntrySnapshot {
    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let date = entry.date ?? entry.createdAt ?? Date()
        self.init(
            id: id,
            date: date,
            updatedAt: entry.updatedAt ?? date,
            mood: entry.value(forKey: "mood") as? String,
            text: text
        )
    }
}

// MARK: - Controller

actor ProactiveReflectionAnalysisWorker {
    func analyze(
        entries: [ReflectionEntrySnapshot],
        existingFollowUps: [DecisionFollowUpState],
        now: Date
    ) async -> ProactiveReflectionAnalysisResult {
        if Task.isCancelled {
            return ProactiveReflectionAnalysisResult(
                insights: [],
                decisions: [],
                followUpStates: existingFollowUps,
                weeklyRecap: nil,
                selectedPrompt: nil
            )
        }
        return ProactiveReflectionAnalyzer.analyze(entries: entries, existingFollowUps: existingFollowUps, now: now)
    }
}

@MainActor
final class ProactiveReflectionController: ObservableObject {
    static let shared = ProactiveReflectionController()

    @Published private(set) var insights: [ReflectionInsight] = []
    @Published private(set) var decisionMoments: [DecisionMoment] = []
    @Published private(set) var followUpStates: [DecisionFollowUpState] = []
    @Published private(set) var weeklyRecap: WeeklyReflectionRecap?
    @Published private(set) var selectedPrompt: ReflectionInsight?
    @Published private(set) var cardFeedback: [String: ReflectionCardFeedback] = [:]

    private let stateType = "proactive_reflection_loop"
    private let feedbackStateType = "proactive_reflection_card_feedback"
    private let debounceInterval: TimeInterval = 1.5
    private let analysisWorker = ProactiveReflectionAnalysisWorker()
    private let persistsChanges: Bool
    private var lastInputSignature: String?
    private var lastRefreshAt: Date?
    private var analysisTask: Task<Void, Never>?

    private init() {
        persistsChanges = true
        load()
    }

    #if DEBUG
    init(loadPersistedState: Bool) {
        persistsChanges = loadPersistedState
        if loadPersistedState {
            load()
        }
    }
    #endif

    @discardableResult
    func refreshIfNeeded(entries: [DiaryEntry], now: Date = Date(), force: Bool = false) -> Task<Void, Never>? {
        let snapshots = entries.compactMap(ReflectionEntrySnapshot.init(entry:))
        let signature = inputSignature(for: snapshots)
        if !force, signature == lastInputSignature, let lastRefreshAt, now.timeIntervalSince(lastRefreshAt) < debounceInterval {
            return nil
        }
        return refresh(snapshots: snapshots, signature: signature, now: now)
    }

    @discardableResult
    func refresh(entries: [DiaryEntry], now: Date = Date()) -> Task<Void, Never>? {
        let snapshots = entries.compactMap(ReflectionEntrySnapshot.init(entry:))
        return refresh(snapshots: snapshots, signature: inputSignature(for: snapshots), now: now)
    }

    func markPrompted(_ insight: ReflectionInsight, now: Date = Date()) {
        guard let decisionID = insight.decisionID else { return }
        updateFollowUp(decisionID: decisionID, state: .prompted, now: now)
    }

    func markReflected(_ insight: ReflectionInsight, now: Date = Date()) {
        guard let decisionID = insight.decisionID else { return }
        updateFollowUp(decisionID: decisionID, state: .reflected, now: now)
    }

    func feedback(for insight: ReflectionInsight) -> ReflectionCardFeedback? {
        cardFeedback[insight.feedbackKey]
    }

    func toggleSaved(_ insight: ReflectionInsight, now: Date = Date()) {
        var feedback = cardFeedback[insight.feedbackKey] ?? ReflectionCardFeedback(
            insightID: insight.feedbackKey,
            saved: false,
            dismissedAt: nil,
            snoozedUntil: nil,
            notUsefulReason: nil,
            updatedAt: now
        )
        feedback.saved.toggle()
        feedback.updatedAt = now
        cardFeedback[insight.feedbackKey] = feedback
        insights = rankedVisibleInsights(insights, now: now)
        saveFeedback()
    }

    func snooze(_ insight: ReflectionInsight, until date: Date? = nil, now: Date = Date()) {
        var feedback = cardFeedback[insight.feedbackKey] ?? ReflectionCardFeedback(
            insightID: insight.feedbackKey,
            saved: false,
            dismissedAt: nil,
            snoozedUntil: nil,
            notUsefulReason: nil,
            updatedAt: now
        )
        feedback.snoozedUntil = date ?? Calendar.current.date(byAdding: .day, value: 3, to: now)
        feedback.updatedAt = now
        cardFeedback[insight.feedbackKey] = feedback
        insights = rankedVisibleInsights(insights, now: now)
        if selectedPrompt?.id == insight.id { selectedPrompt = insights.first }
        saveFeedback()
        refreshReminderSchedule()
    }

    func dismiss(_ insight: ReflectionInsight, now: Date = Date()) {
        var feedback = cardFeedback[insight.feedbackKey] ?? ReflectionCardFeedback(
            insightID: insight.feedbackKey,
            saved: false,
            dismissedAt: nil,
            snoozedUntil: nil,
            notUsefulReason: nil,
            updatedAt: now
        )
        feedback.dismissedAt = now
        feedback.updatedAt = now
        cardFeedback[insight.feedbackKey] = feedback
        insights = rankedVisibleInsights(insights, now: now)
        if selectedPrompt?.id == insight.id { selectedPrompt = insights.first }
        saveFeedback()
        refreshReminderSchedule()
    }

    func markNotUseful(_ insight: ReflectionInsight, reason: String = "Not useful", now: Date = Date()) {
        var feedback = cardFeedback[insight.feedbackKey] ?? ReflectionCardFeedback(
            insightID: insight.feedbackKey,
            saved: false,
            dismissedAt: nil,
            snoozedUntil: nil,
            notUsefulReason: nil,
            updatedAt: now
        )
        feedback.notUsefulReason = reason
        feedback.dismissedAt = now
        feedback.updatedAt = now
        cardFeedback[insight.feedbackKey] = feedback
        insights = rankedVisibleInsights(insights, now: now)
        if selectedPrompt?.id == insight.id { selectedPrompt = insights.first }
        saveFeedback()
        refreshReminderSchedule()
    }

    func privacySafeReminderBody() -> String {
        Self.privacySafeReminderBody(for: selectedPrompt)
    }

    nonisolated static func cachedPrivacySafeReminderBody() -> String {
        UserDefaults.standard.string(forKey: proactiveReflectionReminderBodyKey) ?? privacySafeReminderBody(for: nil)
    }

    nonisolated static func privacySafeReminderBody(for prompt: ReflectionInsight?) -> String {
        // Bodies stay generic: never names, topics, or anything else from the journal.
        guard let prompt else {
            return String(localized: "How was today?")
        }

        switch prompt.category {
        case .decision:
            return String(localized: "Time to check in on a decision.")
        case .weekly:
            return String(localized: "Your weekly reflection is ready.")
        case .pattern:
            return String(localized: "I spotted a pattern worth a look.")
        case .prompt:
            return prompt.decisionID == nil ? String(localized: "I have a question for you tonight.") : String(localized: "Time to check in on a decision.")
        }
    }

    struct Payload: Codable {
        var version: Int
        var insights: [ReflectionInsight]
        var decisionMoments: [DecisionMoment]
        var followUpStates: [DecisionFollowUpState]
        var weeklyRecap: WeeklyReflectionRecap?
        var selectedPrompt: ReflectionInsight?
        var lastInputSignature: String?
        var cardFeedback: [String: ReflectionCardFeedback]? = nil
    }

    struct FeedbackPayload: Codable, Equatable {
        var version: Int
        var cardFeedback: [String: ReflectionCardFeedback]
    }

    @discardableResult
    private func refresh(snapshots: [ReflectionEntrySnapshot], signature: String, now: Date) -> Task<Void, Never> {
        analysisTask?.cancel()
        let existingFollowUps = followUpStates
        lastInputSignature = signature
        lastRefreshAt = now
        let task = Task { [analysisWorker] in
            let result = await analysisWorker.analyze(entries: snapshots, existingFollowUps: existingFollowUps, now: now)
            guard !Task.isCancelled, self.lastInputSignature == signature else { return }
            self.apply(result: result, signature: signature, now: now)
        }
        analysisTask = task
        return task
    }

    private func apply(result: ProactiveReflectionAnalysisResult, signature: String, now: Date) {
        insights = rankedVisibleInsights(result.insights, now: now)
        decisionMoments = result.decisions
        followUpStates = result.followUpStates
        weeklyRecap = result.weeklyRecap
        selectedPrompt = visiblePrompt(result.selectedPrompt, fallback: insights.first, now: now)
        lastInputSignature = signature
        lastRefreshAt = now
        cacheReminderBody()
        save()
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }

    private func updateFollowUp(decisionID: String, state: DecisionFollowUpState.State, now: Date) {
        guard let index = followUpStates.firstIndex(where: { $0.decisionID == decisionID }) else { return }
        followUpStates[index].state = state
        if state == .prompted {
            followUpStates[index].lastPromptedAt = now
        }
        if state == .reflected || state == .dismissed {
            followUpStates[index].resolvedAt = now
        }
        decisionMoments = decisionMoments.map { decision in
            guard decision.id == decisionID else { return decision }
            var updated = decision
            updated.followUp = followUpStates[index]
            return updated
        }
        save()
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }

    private func cacheReminderBody() {
        UserDefaults.standard.set(Self.privacySafeReminderBody(for: selectedPrompt), forKey: proactiveReflectionReminderBodyKey)
    }

    private func refreshReminderSchedule() {
        cacheReminderBody()
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }

    private func save() {
        guard persistsChanges else { return }
        let payload = Payload(
            version: 3,
            insights: insights,
            decisionMoments: decisionMoments,
            followUpStates: followUpStates,
            weeklyRecap: weeklyRecap,
            selectedPrompt: selectedPrompt,
            lastInputSignature: lastInputSignature,
            cardFeedback: nil
        )
        save(payload: payload, stateType: stateType, failureMessage: "Failed to save proactive reflection payload")
    }

    private func saveFeedback() {
        guard persistsChanges else { return }
        let payload = FeedbackPayload(version: 1, cardFeedback: cardFeedback)
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            proactiveReflectionLogger.error("Failed to encode proactive reflection feedback: \(error.localizedDescription, privacy: .public)")
            return
        }
        save(data: data, stateType: feedbackStateType, failureMessage: "Failed to save proactive reflection feedback")
    }

    private func save(payload: Payload, stateType: String, failureMessage: String) {
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            proactiveReflectionLogger.error("\(failureMessage): \(error.localizedDescription, privacy: .public)")
            return
        }
        save(data: data, stateType: stateType, failureMessage: failureMessage)
    }

    private func save(data: Data, stateType: String, failureMessage: String) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            do {
                let request = NSFetchRequest<AIState>(entityName: "AIState")
                request.predicate = NSPredicate(format: "type == %@", stateType)
                request.fetchLimit = 1
                let existing = try context.fetch(request).first
                let state = existing ?? AIState(context: context)
                if existing == nil {
                    state.id = UUID()
                    state.type = stateType
                }
                state.payload = data
                state.updatedAt = Date()
                try context.save()
            } catch {
                proactiveReflectionLogger.error("\(failureMessage): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func load() {
        let migratedFeedback = loadReflectionState()
        loadFeedbackState(migratedFeedback: migratedFeedback)
        insights = rankedVisibleInsights(insights, now: Date())
        selectedPrompt = visiblePrompt(selectedPrompt, fallback: insights.first, now: Date())
        cacheReminderBody()
    }

    private func loadReflectionState() -> [String: ReflectionCardFeedback]? {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", stateType)
        request.fetchLimit = 1
        guard let state = try? context.fetch(request).first, let data = state.payload else { return nil }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.version == 2 || payload.version == 3 else { return nil }
            insights = payload.insights
            decisionMoments = payload.decisionMoments
            followUpStates = payload.followUpStates
            weeklyRecap = payload.weeklyRecap
            selectedPrompt = payload.selectedPrompt
            lastInputSignature = payload.lastInputSignature
            return payload.cardFeedback
        } catch {
            proactiveReflectionLogger.notice("Ignoring old proactive reflection payload; it will rebuild on refresh.")
            return nil
        }
    }

    private func loadFeedbackState(migratedFeedback: [String: ReflectionCardFeedback]?) {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", feedbackStateType)
        request.fetchLimit = 1
        if let state = try? context.fetch(request).first, let data = state.payload {
            do {
                let payload = try JSONDecoder().decode(FeedbackPayload.self, from: data)
                guard payload.version == 1 else { return }
                cardFeedback = payload.cardFeedback
                return
            } catch {
                proactiveReflectionLogger.notice("Ignoring old proactive reflection feedback payload.")
            }
        }

        if let migratedFeedback, !migratedFeedback.isEmpty {
            cardFeedback = migratedFeedback
            saveFeedback()
        }
    }

    private func rankedVisibleInsights(_ candidates: [ReflectionInsight], now: Date) -> [ReflectionInsight] {
        candidates
            .filter { insight in
                guard !insight.isExpired(now: now) else { return false }
                guard let feedback = cardFeedback[insight.feedbackKey] else { return true }
                return !feedback.isDismissed && !feedback.isSnoozed(now: now)
            }
            .sorted { lhs, rhs in
                let lhsSaved = cardFeedback[lhs.feedbackKey]?.saved == true
                let rhsSaved = cardFeedback[rhs.feedbackKey]?.saved == true
                if lhsSaved != rhsSaved { return lhsSaved }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.confidence != rhs.confidence { return confidenceRank(lhs.confidence) > confidenceRank(rhs.confidence) }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func visiblePrompt(_ prompt: ReflectionInsight?, fallback: ReflectionInsight?, now: Date) -> ReflectionInsight? {
        guard let prompt else { return fallback }
        guard let feedback = cardFeedback[prompt.feedbackKey] else { return prompt }
        if feedback.isDismissed || feedback.isSnoozed(now: now) { return fallback }
        return prompt
    }

    private func confidenceRank(_ confidence: ReflectionInsight.Confidence) -> Int {
        switch confidence {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    private func inputSignature(for snapshots: [ReflectionEntrySnapshot]) -> String {
        let newest = snapshots.max { $0.updatedAt < $1.updatedAt }
        return [
            "\(snapshots.count)",
            newest?.id.uuidString ?? "none",
            "\(newest?.date.timeIntervalSince1970 ?? 0)",
            "\(newest?.updatedAt.timeIntervalSince1970 ?? 0)"
        ].joined(separator: "|")
    }

    #if DEBUG
    func visibleInsightsForTesting(_ candidates: [ReflectionInsight], now: Date) -> [ReflectionInsight] {
        rankedVisibleInsights(candidates, now: now)
    }

    func replaceFeedbackForTesting(_ feedback: [String: ReflectionCardFeedback]) {
        cardFeedback = feedback
    }
    #endif
}

// MARK: - Friday UI

struct ProactiveReflectionSection: View {
    let entries: [DiaryEntry]
    var onWritePrompt: ((ReflectionInsight) -> Void)?
    @ObservedObject private var controller = ProactiveReflectionController.shared
    @State private var selectedInsight: ReflectionInsight?

    var body: some View {
        Group {
            if !controller.insights.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    todayHeader

                    if let leadInsight {
                        ReflectionInsightCard(
                            insight: leadInsight,
                            isFeatured: true,
                            onReflect: { write(from: leadInsight) },
                            onOpenEvidence: { open(leadInsight) },
                            onSave: { controller.toggleSaved(leadInsight) },
                            onSnooze: { controller.snooze(leadInsight) },
                            onDismiss: { controller.markNotUseful(leadInsight) }
                        )
                        .accessibilityIdentifier("proactiveReflection.card.\(leadInsight.category.rawValue.lowercased())")
                        Color.clear
                            .frame(height: 0)
                            .accessibilityIdentifier("proactiveReflection.leadCard")
                    }

                    if !deckInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                FridayMascotView(pose: .thinking, size: 30)
                                Text("From Friday")
                                    .font(OffRecordTypography.sectionTitle)
                                    .foregroundColor(OffRecordColor.textHeading)
                                    .accessibilityIdentifier("proactiveReflection.section")
                                Spacer()
                            }

                            ForEach(deckInsights) { insight in
                                ReflectionInsightCard(
                                    insight: insight,
                                    isFeatured: false,
                                    onReflect: { write(from: insight) },
                                    onOpenEvidence: { open(insight) },
                                    onSave: { controller.toggleSaved(insight) },
                                    onSnooze: { controller.snooze(insight) },
                                    onDismiss: { controller.markNotUseful(insight) }
                                )
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("proactiveReflection.card.\(insight.category.rawValue.lowercased())")
                                .accessibilityLabel("\(insight.title). " + String(AttributedString(localized: "Based on ^[\(insight.evidence.count) entry](inflect: true).").characters))
                            }
                        }
                    }
                }
            }
        }
        .onAppear { controller.refreshIfNeeded(entries: entries) }
        .onChange(of: entries.count) { _, _ in controller.refreshIfNeeded(entries: entries) }
        .sheet(item: $selectedInsight) { insight in
            ReflectionInsightDetailView(
                insight: insight,
                entries: entries,
                onWritePrompt: onWritePrompt
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var leadInsight: ReflectionInsight? {
        controller.selectedPrompt ?? controller.insights.first
    }

    private var deckInsights: [ReflectionInsight] {
        controller.insights
            .filter { $0.id != leadInsight?.id }
            .prefix(4)
            .map { $0 }
    }

    private var todayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            FridayMascotView(pose: .listening, size: 42)
            Text("Today with Friday")
                .font(OffRecordTypography.sectionTitle)
                .foregroundColor(OffRecordColor.textHeading)
                .accessibilityIdentifier("proactiveReflection.todayWithFriday")
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func open(_ insight: ReflectionInsight) {
        selectedInsight = insight
        if insight.decisionID != nil {
            controller.markPrompted(insight)
        }
        HapticManager.shared.selectionChanged()
    }

    private func write(from insight: ReflectionInsight) {
        controller.markPrompted(insight)
        onWritePrompt?(insight)
        HapticManager.shared.selectionChanged()
    }
}

private struct ReflectionInsightCard: View {
    let insight: ReflectionInsight
    let isFeatured: Bool
    let onReflect: () -> Void
    let onOpenEvidence: () -> Void
    let onSave: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    @ObservedObject private var controller = ProactiveReflectionController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: isFeatured ? 14 : 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(style.fill)
                        .frame(width: isFeatured ? 42 : 36, height: isFeatured ? 42 : 36)
                    Image(systemName: icon)
                        .font(isFeatured ? OffRecordTypography.labelLarge : OffRecordTypography.labelMedium)
                        .foregroundColor(style.foreground)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(insight.category.displayName)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(style.foreground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(style.fill))
                            .overlay(Capsule().stroke(style.border, lineWidth: 1))

                        if !insight.evidence.isEmpty {
                            Label("\(insight.evidence.count)", systemImage: "quote.bubble")
                                .font(OffRecordTypography.labelSmall)
                                .foregroundColor(OffRecordColor.textSecondary)
                                .accessibilityLabel(String(AttributedString(localized: "^[\(insight.evidence.count) entry](inflect: true)").characters))
                        }

                        if insight.confidence == .low {
                            Text("Not Sure Yet")
                                .font(OffRecordTypography.labelSmall)
                                .foregroundColor(OffRecordColor.textPeach)
                        }
                    }

                    Text(insight.title)
                        .font(isFeatured ? OffRecordTypography.sectionTitle : OffRecordTypography.labelMedium)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(insight.message)
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Menu {
                    Button {
                        onSave()
                    } label: {
                        Label(isSaved ? String(localized: "Unsave", comment: "Menu action that removes a Friday insight from saved") : String(localized: "Save", comment: "Menu action that saves a Friday insight"), systemImage: isSaved ? "bookmark.slash" : "bookmark")
                    }
                    Button {
                        onSnooze()
                    } label: {
                        Label("Snooze", systemImage: "clock")
                    }
                    Button(role: .destructive) {
                        onDismiss()
                    } label: {
                        Label("Not Useful", systemImage: "hand.thumbsdown")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(OffRecordTypography.titleSmall)
                        .foregroundColor(OffRecordColor.textTertiary)
                }
                .accessibilityLabel(Text("More", comment: "Accessibility label for the insight card’s options menu"))
                .accessibilityIdentifier("proactiveReflection.cardMenu.\(insight.kind.rawValue)")
            }

            Text(insight.explanation)
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    onReflect()
                } label: {
                    Label(String(localized: "Write", comment: "Button that starts a typed journal entry"), systemImage: "square.and.pencil")
                        .font(OffRecordTypography.labelSmall)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("proactiveReflection.reflect.\(insight.kind.rawValue)")

                NavigationLink(destination: FridayChatView(initialQuestion: insight.suggestedQuestion ?? insight.prompt)) {
                    Label("Ask Friday", systemImage: "bubble.left.and.bubble.right")
                        .font(OffRecordTypography.labelSmall)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("proactiveReflection.askFriday.\(insight.kind.rawValue)")

                if !insight.evidence.isEmpty {
                    Button {
                        onOpenEvidence()
                    } label: {
                        Label("Why?", systemImage: "quote.bubble")
                            .font(OffRecordTypography.labelSmall)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("proactiveReflection.openEvidence.\(insight.kind.rawValue)")
                }
            }
        }
        .padding(isFeatured ? 18 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: isFeatured ? OffRecordColor.surfaceBlush : OffRecordColor.surfaceLavender)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenEvidence()
        }
    }

    private var icon: String {
        switch insight.kind {
        case .patternSignal: return "waveform.path.ecg"
        case .cadenceChange: return "calendar.badge.clock"
        case .volumeChange: return "text.alignleft"
        case .moodTrajectory: return "arrow.down.right"
        case .resurfacedThread: return "arrow.uturn.backward.circle"
        case .contrast: return "arrow.triangle.swap"
        case .decisionFollowUp: return "arrow.triangle.branch"
        case .quietEntity: return "person.crop.circle.badge.questionmark"
        case .moodAssociation: return "bolt.heart"
        case .repeatedQuestion: return "questionmark.bubble"
        case .weeklyRecap: return "calendar"
        case .carryForward: return "sparkles"
        }
    }

    private var style: OffRecordReadableTintStyle {
        switch insight.category {
        case .pattern: return .growth
        case .decision: return .journal
        case .weekly: return .export
        case .prompt: return .friday
        }
    }

    private var isSaved: Bool {
        controller.feedback(for: insight)?.saved == true
    }
}

private struct ReflectionInsightDetailView: View {
    let insight: ReflectionInsight
    let entries: [DiaryEntry]
    var onWritePrompt: ((ReflectionInsight) -> Void)?
    @ObservedObject private var controller = ProactiveReflectionController.shared
    @Environment(\.dismiss) private var dismiss

    private var sourceEvidence: [ReflectionEvidence] {
        insight.evidence.filter { $0.role == .source || $0.role == .trajectory }
    }

    private var baselineEvidence: [ReflectionEvidence] {
        insight.evidence.filter { $0.role == .baseline }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.category.displayName)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundColor(OffRecordColor.textLavender)
                            .accessibilityIdentifier("proactiveReflection.detail")
                        Text(insight.title)
                            .font(OffRecordTypography.titleLarge)
                            .foregroundColor(OffRecordColor.textHeading)
                        Text(insight.message)
                            .font(OffRecordTypography.bodyMedium)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Why You’re Seeing This", systemImage: "quote.bubble")
                            .font(OffRecordTypography.sectionTitle)
                            .foregroundColor(OffRecordColor.textHeading)
                        Text(insight.explanation)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if insight.confidence == .low {
                            Text("I’m not sure about this one. It’s based on only a few entries.")
                                .font(OffRecordTypography.labelSmall)
                                .foregroundColor(OffRecordColor.textPeach)
                        }
                    }
                    .padding()
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Question", systemImage: "sparkles")
                            .font(OffRecordTypography.sectionTitle)
                            .foregroundColor(OffRecordColor.textHeading)
                        Text(insight.prompt)
                            .font(OffRecordTypography.bodyLarge)
                            .foregroundColor(OffRecordColor.textPrimary)
                    }
                    .padding()
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePeach)

                    HStack(spacing: 10) {
                        if let onWritePrompt {
                            Button {
                                controller.markPrompted(insight)
                                onWritePrompt(insight)
                                dismiss()
                            } label: {
                                Label("Write About This", systemImage: "square.and.pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        NavigationLink(destination: FridayChatView(initialQuestion: insight.suggestedQuestion ?? insight.prompt)) {
                            Label("Ask Friday", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("proactiveReflection.detail.askFriday")

                        if insight.decisionID != nil {
                            Button {
                                controller.markReflected(insight)
                                dismiss()
                            } label: {
                                Label("Mark as Done", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("proactiveReflection.markReflected")
                        }
                    }

                    evidenceSection(
                        title: sourceEvidence.count == 1 ? String(localized: "This Entry") : String(localized: "Recent Entries"),
                        identifier: "proactiveReflection.evidence.source",
                        evidence: sourceEvidence
                    )
                    evidenceSection(
                        title: String(localized: "Earlier Entries"),
                        identifier: "proactiveReflection.evidence.baseline",
                        evidence: baselineEvidence
                    )
                }
                .padding(OffRecordSpacing.xxl)
            }
            .background(OffRecordAppBackground().ignoresSafeArea())
            .navigationTitle("From Friday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceSection(title: String, identifier: String, evidence: [ReflectionEvidence]) -> some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "quote.bubble.fill")
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundColor(OffRecordColor.textHeading)
                    .accessibilityIdentifier(identifier)

                ForEach(evidence) { evidence in
                    if let entry = entry(for: evidence) {
                        NavigationLink {
                            EntryDetailView(entry: entry)
                        } label: {
                            evidenceCard(for: evidence)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("proactiveReflection.evidence.entryLink")
                    } else {
                        evidenceCard(for: evidence)
                    }
                }
            }
        }
    }

    private func evidenceCard(for evidence: ReflectionEvidence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(evidence.date, style: .date)
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textSecondary)
            HStack(spacing: 6) {
                Text(roleLabel(for: evidence.role))
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordColor.textLavender)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(OffRecordColor.backgroundLavenderTint))
                if let mood = evidence.mood, !mood.isEmpty {
                    Text(Mood(rawValue: mood)?.displayName ?? mood.capitalized)
                        .font(OffRecordTypography.labelSmall)
                        .foregroundColor(OffRecordColor.textSage)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(OffRecordColor.backgroundSageTint))
                }
            }
            Text(snippet(for: evidence))
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                .fill(OffRecordColor.surfaceWarm)
        )
    }

    private func roleLabel(for role: ReflectionEvidence.Role) -> String {
        switch role {
        case .source: return String(localized: "Recent", comment: "Tag on an entry cited as recent evidence for a Friday insight")
        case .baseline: return String(localized: "Earlier", comment: "Tag on an entry cited as earlier, comparison evidence for a Friday insight")
        case .trajectory: return String(localized: "Trend", comment: "Tag on an entry cited as part of a mood trend")
        }
    }

    private func snippet(for evidence: ReflectionEvidence) -> String {
        guard let entry = entry(for: evidence),
              let text = entry.text,
              !text.isEmpty else {
            return String(localized: "No text.")
        }
        return ProactiveReflectionAnalyzer.snippet(text)
    }

    private func entry(for evidence: ReflectionEvidence) -> DiaryEntry? {
        entries.first(where: { $0.id == evidence.entryID })
    }
}

// MARK: - Today / Insights UI

struct ProactiveReflectionPromptCard: View {
    let entries: [DiaryEntry]
    let hasEntryToday: Bool
    let onWrite: (ReflectionInsight) -> Void
    @ObservedObject private var controller = ProactiveReflectionController.shared

    var body: some View {
        Group {
            if !hasEntryToday, let prompt = controller.selectedPrompt, prompt.priority == .high {
                Button {
                    controller.markPrompted(prompt)
                    onWrite(prompt)
                    HapticManager.shared.selectionChanged()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(OffRecordColor.backgroundLavenderTint)
                                .frame(width: 38, height: 38)
                            Image(systemName: "sparkles")
                                .font(OffRecordTypography.labelMedium)
                                .foregroundColor(OffRecordColor.textLavender)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(prompt.title)
                                .font(OffRecordTypography.labelMedium)
                                .foregroundColor(OffRecordColor.textHeading)
                            Text(prompt.prompt)
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .font(OffRecordTypography.labelMedium)
                            .foregroundColor(OffRecordColor.textLavender)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceBlush)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("proactiveReflection.todayPrompt")
                .accessibilityLabel(String(AttributedString(localized: "Prompt from Friday, based on ^[\(prompt.evidence.count) entry](inflect: true)").characters))
                .accessibilityHint("Starts an entry with this prompt.")
            }
        }
        .onAppear { controller.refreshIfNeeded(entries: entries) }
    }
}

struct ProactiveWeeklyReflectionCard: View {
    let entries: [DiaryEntry]
    @ObservedObject private var controller = ProactiveReflectionController.shared

    var body: some View {
        Group {
            if let recap = controller.weeklyRecap {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(OffRecordColor.textAqua)
                        Text("Weekly Reflection")
                            .font(OffRecordTypography.sectionTitle)
                            .foregroundColor(OffRecordColor.textHeading)
                        Spacer()
                    }

                    Text(recap.summary)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !recap.topTopics.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(recap.topTopics, id: \.self) { topic in
                                Text(topic)
                                    .font(OffRecordTypography.labelSmall)
                                    .foregroundColor(OffRecordColor.textAqua)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(OffRecordColor.surfaceMint))
                            }
                        }
                    }

                    Text(recap.suggestedPrompt)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                                .fill(OffRecordColor.surfaceWarm)
                        )
                }
                .padding()
                .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
                .accessibilityIdentifier("proactiveReflection.weeklyRecap")
            }
        }
        .onAppear { controller.refreshIfNeeded(entries: entries) }
        .onChange(of: entries.count) { _, _ in controller.refreshIfNeeded(entries: entries) }
    }
}
