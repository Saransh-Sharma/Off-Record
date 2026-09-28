import SwiftUI

struct TodayHeroEntryPreviewCard: View {
    @ObservedObject var entry: DiaryEntry
    let isNight: Bool

    var body: some View {
        NavigationLink {
            EntryDetailView(entry: entry)
        } label: {
            HStack(spacing: 14) {
                OffRecordIconBubble(
                    systemImage: isNight ? "sparkles" : "book.closed.fill",
                    tint: isNight ? OffRecordColor.textInverse.opacity(0.86) : OffRecordColor.brandLavenderDark,
                    fill: isNight ? OffRecordColor.textInverse.opacity(0.14) : OffRecordColor.backgroundLavenderTint,
                    size: 44,
                    iconSize: 17
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Today", comment: "Heading of the card that previews today’s entry")
                        .accessibilityAddTraits(.isHeader)
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(primaryText)

                    Text(metadataText)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(secondaryText)

                    Text(previewText)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                        .accessibilityIdentifier("todayEntry.preview")
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(OffRecordTypography.labelLarge)
                    .foregroundStyle(secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OffRecordSpacing.lg)
            .padding(.vertical, OffRecordSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: cardFill)
            .contentShape(RoundedRectangle(cornerRadius: OffRecordRadius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today’s entry")
        .accessibilityIdentifier("homeHero.todayEntryPreview")
    }

    private var previewText: String {
        let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
        if entry.hasStartedEntryAudio {
            return String(localized: "Recording saved.")
        }
        if entry.photos?.count ?? 0 > 0 {
            return String(localized: "Photos added.")
        }
        return String(localized: "Draft", comment: "Stands in for today’s entry preview when the entry is still empty")
    }

    private var metadataText: String {
        let updatedAt = entry.updatedAt ?? entry.date ?? Date()
        let time = updatedAt.formatted(date: .omitted, time: .shortened)
        let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let words = text.isEmpty ? 0 : text.split { $0.isWhitespace || $0.isNewline }.count
        let wordCount = String(AttributedString(localized: "^[\(words) word](inflect: true)").characters)
        return String(localized: "Updated \(time) · \(wordCount)", comment: "Today’s entry preview metadata: last edit time, then word count")
    }

    private var primaryText: Color {
        isNight ? OffRecordColor.textInverse : OffRecordColor.textBrand
    }

    private var secondaryText: Color {
        isNight ? Color(hex: 0xD9CFDD) : OffRecordColor.textSecondary
    }

    /// Opaque enough that small metadata stays readable over any part of the illustration.
    private var cardFill: Color {
        isNight ? OffRecordColor.darkSurface.opacity(0.86) : OffRecordColor.surfacePrimary
    }

    private var cardBorder: Color {
        isNight ? OffRecordColor.textInverse.opacity(0.20) : OffRecordColor.borderSoft
    }
}
