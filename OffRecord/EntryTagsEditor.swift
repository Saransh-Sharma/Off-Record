//
//  EntryTagsEditor.swift
//  OffRecord
//
//  Tags on an open entry: a row of tag chips with an Add Tag pill, and a
//  small sheet that adds tags with suggestions from existing ones and
//  removes them. Tag names are trimmed and unique ignoring case, so typing
//  "work" reuses an existing "Work".
//

import CoreData
import SwiftUI

struct EntryTagsRow: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isEditing = false

    var body: some View {
        let tags = TagStore(context: viewContext).tags(for: entry)
        FlowLayout(spacing: OffRecordSpacing.sm) {
            ForEach(tags, id: \.objectID) { tag in
                Button {
                    isEditing = true
                } label: {
                    TagChipLabel(name: tag.name ?? "")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        remove(tag)
                    } label: {
                        Label(String(localized: "Remove Tag"), systemImage: "minus.circle")
                    }
                }
                .accessibilityLabel(String(localized: "Tag, \(tag.name ?? "")", comment: "VoiceOver: a tag on this entry"))
                .accessibilityHint(String(localized: "Edits this entry’s tags.", comment: "VoiceOver hint for a tag chip"))
                .accessibilityIdentifier("entryDetail.tag.\(tag.name ?? "")")
            }

            Button {
                isEditing = true
            } label: {
                Label(String(localized: "Add Tag"), systemImage: "number")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .padding(.horizontal, OffRecordSpacing.md)
                    .frame(minHeight: 32)
                    .background(OffRecordColor.surfacePrimary.opacity(0.68), in: Capsule())
                    .overlay(Capsule().stroke(OffRecordColor.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entryDetail.addTag")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entryDetail.tags")
        .sheet(isPresented: $isEditing) {
            EntryTagEditorSheet(entry: entry)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func remove(_ tag: JournalTag) {
        do {
            try TagStore(context: viewContext).removeTag(tag, from: entry)
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
        }
    }
}

/// A tag as a small neutral pill: "# Work".
struct TagChipLabel: View {
    let name: String
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "number")
                .font(OffRecordTypography.annotation)
                .foregroundStyle(OffRecordColor.textTertiary)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
        }
        .font(OffRecordTypography.metadata)
        .foregroundStyle(OffRecordReadableTintStyle.neutral.foreground)
        .padding(.horizontal, compact ? OffRecordSpacing.sm : OffRecordSpacing.md)
        .frame(minHeight: compact ? 24 : 32)
        .background(OffRecordReadableTintStyle.neutral.fill, in: Capsule())
        .overlay(Capsule().stroke(OffRecordReadableTintStyle.neutral.border, lineWidth: 1))
    }
}

struct EntryTagEditorSheet: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))])
    private var allTags: FetchedResults<JournalTag>
    @State private var text = ""
    @FocusState private var isFieldFocused: Bool
    @State private var showsError = false

    private var store: TagStore { TagStore(context: viewContext) }
    private var entryTags: [JournalTag] { store.tags(for: entry) }
    private var typedName: String { TagStore.normalizedName(text) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: OffRecordSpacing.sm) {
                        Image(systemName: "number")
                            .foregroundStyle(OffRecordColor.textTertiary)
                            .accessibilityHidden(true)
                        TextField(String(localized: "Tag name"), text: $text)
                            .focused($isFieldFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { addTyped() }
                            .accessibilityIdentifier("tagEditor.field")
                    }
                }

                if !typedName.isEmpty {
                    Section(String(localized: "Suggestions", comment: "Existing tags that match what was typed")) {
                        if !hasExactMatch {
                            Button {
                                addTyped()
                            } label: {
                                Label(String(localized: "Add “\(typedName)”", comment: "Creates a tag with the typed name"), systemImage: "plus.circle")
                            }
                            .accessibilityIdentifier("tagEditor.create")
                        }
                        ForEach(suggestions, id: \.objectID) { tag in
                            suggestionRow(tag)
                        }
                    }
                } else if !otherTags.isEmpty {
                    Section(String(localized: "All Tags", comment: "Tags not yet on this entry")) {
                        ForEach(otherTags, id: \.objectID) { tag in
                            suggestionRow(tag)
                        }
                    }
                }

                if !entryTags.isEmpty {
                    Section(String(localized: "On This Entry", comment: "Tags on the open entry")) {
                        ForEach(entryTags, id: \.objectID) { tag in
                            HStack {
                                TagChipLabel(name: tag.name ?? "")
                                Spacer(minLength: OffRecordSpacing.sm)
                                Button {
                                    remove(tag)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(OffRecordColor.textCoral)
                                        .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Remove \(tag.name ?? "")", comment: "VoiceOver: removes a tag from the entry"))
                                .accessibilityIdentifier("tagEditor.remove.\(tag.name ?? "")")
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Tags"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        if !typedName.isEmpty { addTyped() }
                        dismiss()
                    }
                    .accessibilityIdentifier("tagEditor.done")
                }
            }
            .onAppear { isFieldFocused = true }
            .alert(String(localized: "Couldn’t Save Tag"), isPresented: $showsError) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text("Try again.", comment: "Message when a tag change fails to save")
            }
        }
    }

    private var hasExactMatch: Bool {
        allTags.contains { ($0.name ?? "").compare(typedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private var suggestions: [JournalTag] {
        store.suggestions(for: typedName, excluding: Set(entryTags.map(\.objectID)))
    }

    private var otherTags: [JournalTag] {
        let onEntry = Set(entryTags.map(\.objectID))
        return allTags.filter { !onEntry.contains($0.objectID) }
    }

    private func suggestionRow(_ tag: JournalTag) -> some View {
        Button {
            add(named: tag.name ?? "")
        } label: {
            HStack {
                TagChipLabel(name: tag.name ?? "")
                Spacer(minLength: OffRecordSpacing.sm)
                Image(systemName: "plus")
                    .foregroundStyle(OffRecordColor.textBrand)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add \(tag.name ?? "")", comment: "VoiceOver: adds an existing tag to the entry"))
        .accessibilityIdentifier("tagEditor.suggestion.\(tag.name ?? "")")
    }

    private func addTyped() {
        guard !typedName.isEmpty else { return }
        add(named: typedName)
    }

    private func add(named name: String) {
        do {
            try store.addTag(named: name, to: entry)
            text = ""
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
            showsError = true
        }
    }

    private func remove(_ tag: JournalTag) {
        do {
            try store.removeTag(tag, from: entry)
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
            showsError = true
        }
    }
}
