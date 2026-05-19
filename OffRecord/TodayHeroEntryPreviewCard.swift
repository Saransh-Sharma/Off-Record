import SwiftUI

struct TodayHeroEntryPreviewCard: View {
    let entry: DiaryEntry
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
                    Text("Today's entry")
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(primaryText)

                    Text(metadataText)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(secondaryText)

                    Text(previewText)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundStyle(primaryText.opacity(isNight ? 0.94 : 0.88))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(cardBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's entry")
        .accessibilityIdentifier("homeHero.todayEntryPreview")
    }

    private var previewText: String {
        let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
        if (entry.value(forKey: "audioFileName") as? String)?.isEmpty == false {
            return "Recording saved. Tap to add text or play your recording."
        }
        if entry.photos?.count ?? 0 > 0 {
            return "Photos added. Tap to add text or more photos."
        }
        return "Draft note. Tap to start writing."
    }

    private var metadataText: String {
        let updatedAt = entry.updatedAt ?? entry.date ?? Date()
        let time = updatedAt.formatted(date: .omitted, time: .shortened)
        let words = previewText.split { $0.isWhitespace || $0.isNewline }.count
        return "\(time) - \(words) \(words == 1 ? "word" : "words")"
    }

    private var primaryText: Color {
        isNight ? OffRecordColor.textInverse : OffRecordColor.textBrand
    }

    private var secondaryText: Color {
        isNight ? OffRecordColor.backgroundSecondary : OffRecordColor.textSecondary
    }

    private var cardFill: Color {
        isNight ? OffRecordColor.darkSurface.opacity(0.56) : OffRecordColor.surfacePrimary.opacity(0.78)
    }

    private var cardBorder: Color {
        isNight ? OffRecordColor.textInverse.opacity(0.20) : OffRecordColor.borderSoft
    }
}
