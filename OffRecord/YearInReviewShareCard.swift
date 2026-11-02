//
//  YearInReviewShareCard.swift
//  OffRecord
//
//  The Year in Review share image. People's names are replaced with
//  "someone" unless the person turns names on, using the same redaction as
//  shared insight cards.
//

import SwiftUI

struct YearInReviewShareContent: Equatable {
    var year: Int
    var entryCount: Int
    var activeDays: Int
    var wordCount: Int
    var recordedMinutes: Int
    var people: [String]
    var topics: [String]
    var moodDays: [PeriodReviewMoodDay]
    var periodStart: Date

    init(year: Int, entryCount: Int, activeDays: Int, wordCount: Int, recordedMinutes: Int, people: [String], topics: [String], moodDays: [PeriodReviewMoodDay], periodStart: Date) {
        self.year = year
        self.entryCount = entryCount
        self.activeDays = activeDays
        self.wordCount = wordCount
        self.recordedMinutes = recordedMinutes
        self.people = people
        self.topics = topics
        self.moodDays = moodDays
        self.periodStart = periodStart
    }

    /// The card for a stored review, with forgotten items removed and renamed items relabeled.
    @MainActor
    init(review: PeriodReview, preferences: FridayMemoryPreferences? = nil) {
        let preferences = preferences ?? .shared
        func visible(_ mentions: [PeriodReviewMention]) -> [String] {
            mentions.compactMap { mention in
                if let id = mention.nodeID, preferences.forgottenIDs.contains(id) { return nil }
                if preferences.isForgottenLabel(mention.label) { return nil }
                if let id = mention.nodeID, let alias = preferences.aliases[id], !alias.isEmpty { return alias }
                return mention.label
            }
        }
        self.init(
            year: Calendar.current.component(.year, from: review.report.periodStart),
            entryCount: review.stats.entryCount,
            activeDays: review.stats.activeDays,
            wordCount: review.stats.wordCount,
            recordedMinutes: review.stats.recordedMinutes,
            people: Array(visible(review.stats.topPeople).prefix(3)),
            topics: Array(visible(review.stats.topTopics).prefix(3)),
            moodDays: review.stats.moodDays,
            periodStart: review.report.periodStart
        )
    }

    /// Names to hide: the top people plus any names NaturalLanguage spots in the topics.
    var namesToProtect: [String] {
        var names = people
        for name in ShareableInsightPrivacy.detectedNames(in: topics) where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// What goes in the image. Hidden names become "someone", listed once.
    func sharingVersion(includeNames: Bool) -> YearInReviewShareContent {
        let names = namesToProtect
        guard !includeNames, !names.isEmpty else { return self }
        var copy = self
        var redactedPeople: [String] = []
        for person in people.map({ ShareableInsightPrivacy.redact($0, names: names) }) where !redactedPeople.contains(where: { $0.caseInsensitiveCompare(person) == .orderedSame }) {
            redactedPeople.append(person)
        }
        copy.people = redactedPeople.map { $0.prefix(1).lowercased() + $0.dropFirst() }
        copy.topics = topics.map { ShareableInsightPrivacy.redact($0, names: names) }
        return copy
    }

    /// Every line of text the image shows, for tests and VoiceOver.
    var visibleLines: [String] {
        var lines = [
            String(year),
            String(AttributedString(localized: "^[\(entryCount) entry](inflect: true) on ^[\(activeDays) day](inflect: true)").characters),
            String(localized: "\(wordCount.formatted()) words · \(recordedMinutes.formatted()) minutes recorded")
        ]
        if !topics.isEmpty { lines.append(String(localized: "Topics: \(topics.formatted(.list(type: .and)))")) }
        if !people.isEmpty { lines.append(String(localized: "People: \(people.formatted(.list(type: .and)))")) }
        return lines
    }
}

struct YearInReviewShareCardView: View {
    let content: YearInReviewShareContent

    var body: some View {
        let lines = content.visibleLines
        VStack(alignment: .leading, spacing: 16) {
            Label("Year in Review", systemImage: "sparkles.rectangle.stack")
                .font(OffRecordExportTypography.label)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(OffRecordColor.textLavender)
            Text(lines[0])
                .font(OffRecordExportTypography.headline)
                .foregroundStyle(OffRecordColor.textHeading)
            YearInPixelsView(start: content.periodStart, moodDays: content.moodDays, columns: 4)
            ForEach(lines.dropFirst(), id: \.self) { line in
                Text(line)
                    .font(OffRecordExportTypography.body)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("OffRecord")
                .font(OffRecordExportTypography.brand)
                .foregroundStyle(OffRecordColor.textSecondary)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [OffRecordColor.surfaceWarm, OffRecordColor.surfaceLavender], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

enum YearInReviewCardRenderer {
    @MainActor
    static func render(_ content: YearInReviewShareContent) -> UIImage? {
        let view = YearInReviewShareCardView(content: content)
            .frame(width: 380, height: 560)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Shows exactly what will be shared, with names hidden by default.
struct YearInReviewShareSheet: View {
    let content: YearInReviewShareContent
    @Environment(\.dismiss) private var dismiss
    @State private var includeNames = false
    @State private var image: UIImage?

    private var shareable: YearInReviewShareContent { content.sharingVersion(includeNames: includeNames) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffRecordSpacing.xl) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 320)
                            .frame(maxWidth: .infinity)
                            .offRecordShadow(.card)
                            .accessibilityLabel(shareable.visibleLines.joined(separator: ", "))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }

                    if !content.namesToProtect.isEmpty {
                        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                            Toggle(isOn: $includeNames) {
                                Label("Show Names", systemImage: "person.crop.circle")
                                    .font(OffRecordTypography.labelLarge)
                                    .foregroundStyle(OffRecordColor.textPrimary)
                            }
                            .tint(OffRecordColor.brandSageDark)
                            .accessibilityIdentifier("yearInReview.share.includeNames")
                            Text(includeNames
                                 ? String(localized: "Names will be visible in the image.")
                                 : String(localized: "Names are replaced with \u{201C}someone.\u{201D}"))
                                .font(OffRecordTypography.metadata)
                                .foregroundStyle(OffRecordColor.textSecondary)
                        }
                        .padding(OffRecordSpacing.lg)
                        .offRecordCard(cornerRadius: OffRecordRadius.md, shadow: false)
                    }

                    OffRecordPrivacyBadge(title: String(localized: "Only this image is shared."))

                    if let image {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(String(localized: "Year in Review"), image: Image(uiImage: image))) {
                            Label("Share Image", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .offRecordPillButton()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("yearInReview.share.confirm")
                    }
                }
                .padding(OffRecordSpacing.screenX)
                .frame(maxWidth: OffRecordLayout.readableContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(OffRecordAppBackground().ignoresSafeArea())
            .navigationTitle("Share Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: includeNames) {
            image = YearInReviewCardRenderer.render(shareable)
        }
    }
}
