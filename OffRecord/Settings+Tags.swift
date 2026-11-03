//
//  Settings+Tags.swift
//  OffRecord
//
//  Settings › Tags: rename, merge, and delete tags. Renaming a tag to a name
//  another tag already has offers to merge the two. Deleting a tag leaves
//  its entries as they are, without the tag.
//

import CoreData
import SwiftUI

struct TagsSettingsSection: View {
    static let searchKeywords = "tags tag label hashtag rename merge delete organize"

    @FetchRequest(sortDescriptors: [])
    private var tags: FetchedResults<JournalTag>

    var body: some View {
        SettingsCard(
            title: String(localized: "Tags"),
            footer: String(localized: "Search Timeline with # and a tag name."),
            systemImage: "number",
            tint: OffRecordColor.textBrand,
            fill: OffRecordColor.surfacePrimary
        ) {
            NavigationLink {
                TagManagementView()
            } label: {
                SettingsActionRow(
                    systemImage: "number",
                    title: String(localized: "Manage Tags"),
                    subtitle: tags.isEmpty
                        ? String(localized: "No tags yet", comment: "Settings: no tags exist")
                        : String(AttributedString(localized: "^[\(tags.count) tag](inflect: true)").characters),
                    tint: OffRecordColor.textBrand
                )
            }
            .accessibilityIdentifier("settings.tags.manage")
        }
    }
}

struct TagManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))])
    private var tags: FetchedResults<JournalTag>

    @State private var renamingTag: JournalTag?
    @State private var renameText = ""
    @State private var pendingMerge: PendingTagMerge?
    @State private var deletingTag: JournalTag?
    @State private var showsError = false

    private struct PendingTagMerge {
        let source: JournalTag
        let target: JournalTag
    }

    private var store: TagStore { TagStore(context: viewContext) }

    var body: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Tags"), systemImage: "number")
                } description: {
                    Text("Add tags from an entry.")
                }
            } else {
                List {
                    ForEach(tags, id: \.objectID) { tag in
                        row(tag)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Tags"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Rename Tag"), isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField(String(localized: "Name"), text: $renameText)
                .accessibilityIdentifier("settings.tags.nameField")
            Button(String(localized: "Save")) { rename() }
                .accessibilityIdentifier("settings.tags.save")
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(mergeTitle, isPresented: Binding(
            get: { pendingMerge != nil },
            set: { if !$0 { pendingMerge = nil } }
        ), presenting: pendingMerge) { merge in
            Button(String(localized: "Merge")) { perform(merge) }
                .accessibilityIdentifier("settings.tags.merge")
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { merge in
            Text("Entries tagged \(merge.source.name ?? "") will be tagged \(merge.target.name ?? "") instead.", comment: "Merge tags message. The arguments are tag names.")
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { deletingTag != nil },
                set: { if !$0 { deletingTag = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingTag
        ) { tag in
            Button(String(localized: "Delete Tag"), role: .destructive) { delete(tag) }
                .accessibilityIdentifier("settings.tags.deleteConfirm")
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("Its entries stay. Only the tag is removed.")
        }
        .alert(String(localized: "Couldn’t Save Tag"), isPresented: $showsError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text("Try again.", comment: "Message when a tag change fails to save")
        }
    }

    private func row(_ tag: JournalTag) -> some View {
        Button {
            renameText = tag.name ?? ""
            renamingTag = tag
        } label: {
            HStack(spacing: OffRecordSpacing.md) {
                TagChipLabel(name: tag.name ?? "")
                Spacer(minLength: OffRecordSpacing.sm)
                Text(String(AttributedString(localized: "^[\(store.entryCount(for: tag)) entry](inflect: true)").characters))
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Image(systemName: "pencil")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Renames the tag."))
        .accessibilityIdentifier("settings.tags.row.\(tag.name ?? "")")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deletingTag = tag
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                renameText = tag.name ?? ""
                renamingTag = tag
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingTag = tag
            } label: {
                Label(String(localized: "Delete Tag"), systemImage: "trash")
            }
            .accessibilityIdentifier("settings.tags.delete")
        }
    }

    private var mergeTitle: String {
        guard let pendingMerge else { return String(localized: "Merge Tags?") }
        return String(localized: "Merge Into \(pendingMerge.target.name ?? "")?", comment: "Merge tags title. The argument is the tag that stays.")
    }

    private var deleteTitle: String {
        guard let deletingTag else { return String(localized: "Delete Tag?") }
        return String(localized: "Delete \(deletingTag.name ?? "")?", comment: "Delete tag title. The argument is a tag name.")
    }

    private func rename() {
        guard let tag = renamingTag else { return }
        renamingTag = nil
        let name = TagStore.normalizedName(renameText)
        guard !name.isEmpty, name != tag.name else { return }
        if let existing = store.tag(named: name), existing.objectID != tag.objectID {
            // Let the rename alert finish dismissing before the merge alert appears.
            DispatchQueue.main.async { pendingMerge = PendingTagMerge(source: tag, target: existing) }
            return
        }
        do {
            try store.renameOrMerge(tag, to: name)
        } catch {
            viewContext.rollback()
            showsError = true
        }
    }

    private func perform(_ merge: PendingTagMerge) {
        pendingMerge = nil
        do {
            try store.merge(merge.source, into: merge.target)
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
            showsError = true
        }
    }

    private func delete(_ tag: JournalTag) {
        deletingTag = nil
        do {
            try store.deleteTag(tag)
            HapticManager.shared.entryDeleted()
        } catch {
            viewContext.rollback()
            showsError = true
        }
    }
}
