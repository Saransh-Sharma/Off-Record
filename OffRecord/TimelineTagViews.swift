//
//  TimelineTagViews.swift
//  OffRecord
//
//  Tags in Timeline: the chips under an entry card (with the entry's journal
//  when it isn't the main one), the Tag row in the filter bar, and the
//  active-filter chip for the chosen tag.
//

import CoreData
import SwiftUI

/// The entry's journal (when not the main one) and up to three tags, under its preview text.
struct TimelineEntryOrganizationLabels: View {
    let entry: DiaryEntry

    static let maximumVisibleTags = 3

    var body: some View {
        let tags = TagSearch.names(of: entry).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let journal = entry.journal
        if !tags.isEmpty || journal != nil {
            HStack(spacing: 6) {
                if let journal {
                    Label(JournalNames.displayName(for: journal), systemImage: "books.vertical")
                        .labelStyle(.titleAndIcon)
                        .font(OffRecordTypography.annotation)
                        .foregroundStyle(OffRecordReadableTintStyle.journal.foreground)
                        .lineLimit(1)
                }
                ForEach(tags.prefix(Self.maximumVisibleTags), id: \.self) { name in
                    TagChipLabel(name: name, compact: true)
                }
                if tags.count > Self.maximumVisibleTags {
                    Text(verbatim: "+\(tags.count - Self.maximumVisibleTags)")
                        .font(OffRecordTypography.annotation)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(journal: journal, tags: tags))
            .accessibilityIdentifier("timeline.entryTags")
        }
    }

    private func accessibilityText(journal: Journal?, tags: [String]) -> String {
        var parts: [String] = []
        if let journal {
            parts.append(String(localized: "Journal, \(JournalNames.displayName(for: journal))", comment: "VoiceOver: the journal of a Timeline entry"))
        }
        if !tags.isEmpty {
            parts.append(String(localized: "Tags, \(tags.formatted(.list(type: .and)))", comment: "VoiceOver: the tags of a Timeline entry"))
        }
        return parts.joined(separator: ". ")
    }
}

/// The Tag row in Timeline's filter bar. Only shown once a tag exists.
struct TimelineTagFilterRow: View {
    @Binding var selectedTagID: UUID?
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))])
    private var tags: FetchedResults<JournalTag>

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Tag", comment: "Label before the row of tag filters.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)

                    ForEach(tags, id: \.objectID) { tag in
                        let isSelected = tag.id != nil && tag.id == selectedTagID
                        Button {
                            withOffRecordAnimation(OffRecordMotion.snappy) {
                                selectedTagID = isSelected ? nil : tag.id
                            }
                            HapticManager.shared.selectionChanged()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "number")
                                    .font(OffRecordTypography.annotation)
                                    .accessibilityHidden(true)
                                Text(tag.name ?? "")
                                    .lineLimit(1)
                            }
                            .font(OffRecordTypography.metadata)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(isSelected ? OffRecordReadableTintStyle.brand.foreground : OffRecordColor.textSecondary)
                            .offRecordGlassControl(
                                tint: isSelected ? OffRecordReadableTintStyle.brand.tint : nil,
                                in: Capsule(),
                                fallbackFill: isSelected ? OffRecordReadableTintStyle.brand.fill : OffRecordReadableTintStyle.neutral.fill,
                                border: isSelected ? OffRecordReadableTintStyle.brand.border : OffRecordReadableTintStyle.neutral.border
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.name ?? "")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("timeline.tagFilter.\(tag.name ?? "")")
                    }
                }
            }
            .onChange(of: tags.map(\.objectID)) { _, _ in
                // A deleted or merged tag can't stay selected.
                if let selectedTagID, !tags.contains(where: { $0.id == selectedTagID }) {
                    self.selectedTagID = nil
                }
            }
        }
    }
}

/// The active-filter chip for the chosen tag.
struct TimelineTagFilterChip: View {
    let tagID: UUID
    let onRemove: () -> Void
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let name = tagName
        FilterChip(label: "#\(name)", icon: nil, style: .brand, onRemove: onRemove)
            .accessibilityIdentifier("timeline.activeTagFilter")
    }

    private var tagName: String {
        let request: NSFetchRequest<JournalTag> = JournalTag.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first?.name ?? ""
    }
}
