//
//  Settings+Journals.swift
//  OffRecord
//
//  Settings › Journals: create, rename, archive, and delete journals. The main
//  journal is always there and can't be renamed or deleted. Deleting a journal
//  asks whether its entries move to the main journal (merging days that
//  already have a main entry) or are deleted.
//

import CoreData
import SwiftUI

struct JournalsSettingsSection: View {
    static let searchKeywords = "journals journal work travel separate archive organize"

    @FetchRequest(sortDescriptors: JournalFetch.sortDescriptors)
    private var journals: FetchedResults<Journal>

    var body: some View {
        SettingsCard(
            title: String(localized: "Journals"),
            footer: String(localized: "Keep work or travel entries apart from your main journal."),
            systemImage: "books.vertical",
            tint: OffRecordColor.textPeach,
            fill: OffRecordColor.surfacePrimary
        ) {
            NavigationLink {
                JournalManagementView()
            } label: {
                SettingsActionRow(
                    systemImage: "books.vertical",
                    title: String(localized: "Manage Journals"),
                    subtitle: subtitle,
                    tint: OffRecordColor.textPeach
                )
            }
            .accessibilityIdentifier("settings.journals.manage")
        }
    }

    private var subtitle: String {
        let active = journals.filter { !$0.isArchived }.count
        guard active > 0 else { return String(localized: "Only the main journal", comment: "Settings: no journals besides the main one") }
        return String(AttributedString(localized: "Main and ^[\(active) more](inflect: true)", comment: "Settings: the main journal plus a count of other journals").characters)
    }
}

struct JournalManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: JournalFetch.sortDescriptors)
    private var journals: FetchedResults<Journal>
    @FetchRequest(sortDescriptors: [], predicate: DiaryEntry.startedEntryPredicate)
    private var startedEntries: FetchedResults<DiaryEntry>

    @State private var isCreating = false
    @State private var newName = ""
    @State private var renamingJournal: Journal?
    @State private var renameText = ""
    @State private var deletingJournal: Journal?
    @State private var errorMessage: String?

    private var activeJournals: [Journal] { journals.filter { !$0.isArchived } }
    private var archivedJournals: [Journal] { journals.filter(\.isArchived) }

    var body: some View {
        List {
            Section {
                mainRow
                ForEach(activeJournals, id: \.objectID) { journal in
                    journalRow(journal)
                }
            } footer: {
                Text("New recordings and writing go to the journal you last picked.")
            }

            if !archivedJournals.isEmpty {
                Section(String(localized: "Archived", comment: "Settings: archived journals")) {
                    ForEach(archivedJournals, id: \.objectID) { journal in
                        journalRow(journal)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Journals"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = ""
                    isCreating = true
                } label: {
                    Label(String(localized: "New Journal"), systemImage: "plus")
                }
                .accessibilityIdentifier("settings.journals.add")
            }
        }
        .alert(String(localized: "New Journal"), isPresented: $isCreating) {
            TextField(String(localized: "Name"), text: $newName)
                .accessibilityIdentifier("settings.journals.nameField")
            Button(String(localized: "Create")) { create() }
                .accessibilityIdentifier("settings.journals.create")
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(String(localized: "Rename Journal"), isPresented: Binding(
            get: { renamingJournal != nil },
            set: { if !$0 { renamingJournal = nil } }
        )) {
            TextField(String(localized: "Name"), text: $renameText)
            Button(String(localized: "Save")) { rename() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { deletingJournal != nil },
                set: { if !$0 { deletingJournal = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingJournal
        ) { journal in
            Button(String(localized: "Move Entries to Main")) {
                delete(journal, choice: .moveEntriesToMain)
            }
            .accessibilityIdentifier("settings.journals.delete.move")
            Button(String(localized: "Delete Entries"), role: .destructive) {
                delete(journal, choice: .deleteEntries)
            }
            .accessibilityIdentifier("settings.journals.delete.entries")
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { journal in
            Text(deleteMessage(for: journal))
        }
        .alert(String(localized: "Couldn’t Save Journal"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Rows

    private var mainRow: some View {
        HStack(spacing: OffRecordSpacing.md) {
            Image(systemName: JournalNames.defaultIconName)
                .foregroundStyle(OffRecordColor.textBrand)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(JournalNames.main)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                Text(entryCountText(startedEntries.filter { $0.journal == nil }.count))
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
        .frame(minHeight: OffRecordLayout.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.journals.main")
    }

    private func journalRow(_ journal: Journal) -> some View {
        Button {
            renameText = journal.name ?? ""
            renamingJournal = journal
        } label: {
            HStack(spacing: OffRecordSpacing.md) {
                Image(systemName: journal.isArchived ? "archivebox" : (journal.iconName ?? JournalNames.defaultIconName))
                    .foregroundStyle(OffRecordColor.textPeach)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(JournalNames.displayName(for: journal))
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textPrimary)
                    Text(entryCountText(entryCount(in: journal)))
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
                Spacer(minLength: OffRecordSpacing.sm)
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
        .accessibilityHint(String(localized: "Renames the journal."))
        .accessibilityIdentifier("settings.journals.row.\(journal.name ?? "")")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deletingJournal = journal
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            Button {
                setArchived(journal, !journal.isArchived)
            } label: {
                Label(journal.isArchived ? String(localized: "Unarchive") : String(localized: "Archive"), systemImage: journal.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(OffRecordColor.brandPeach)
        }
        .contextMenu {
            Button {
                renameText = journal.name ?? ""
                renamingJournal = journal
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            Button {
                setArchived(journal, !journal.isArchived)
            } label: {
                Label(journal.isArchived ? String(localized: "Unarchive") : String(localized: "Archive"), systemImage: journal.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .accessibilityIdentifier("settings.journals.archive")
            Divider()
            Button(role: .destructive) {
                deletingJournal = journal
            } label: {
                Label(String(localized: "Delete Journal"), systemImage: "trash")
            }
            .accessibilityIdentifier("settings.journals.delete")
        }
    }

    // MARK: Copy

    private var deleteTitle: String {
        guard let deletingJournal else { return String(localized: "Delete Journal?") }
        return String(localized: "Delete \(JournalNames.displayName(for: deletingJournal))?", comment: "Confirmation title. The argument is a journal name.")
    }

    private func deleteMessage(for journal: Journal) -> String {
        let count = entryCount(in: journal)
        guard count > 0 else { return String(localized: "This journal has no entries.") }
        return String(AttributedString(localized: "Its ^[\(count) entry](inflect: true) can move to Main or be deleted.", comment: "Delete journal message").characters)
    }

    private func entryCountText(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) entry](inflect: true)").characters)
    }

    private func entryCount(in journal: Journal) -> Int {
        ((journal.entries as? Set<DiaryEntry>) ?? []).filter { !$0.isDeleted && $0.isStartedEntry }.count
    }

    // MARK: Actions

    private func create() {
        let store = JournalStore(context: viewContext)
        let name = JournalStore.normalizedName(newName)
        guard !name.isEmpty else { return }
        guard !store.isNameTaken(name) else {
            errorMessage = String(localized: "Choose a name no other journal uses.")
            return
        }
        do {
            try store.createJournal(named: name)
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
            errorMessage = String(localized: "Try again.")
        }
    }

    private func rename() {
        guard let journal = renamingJournal else { return }
        renamingJournal = nil
        let store = JournalStore(context: viewContext)
        let name = JournalStore.normalizedName(renameText)
        guard !name.isEmpty, name != journal.name else { return }
        guard !store.isNameTaken(name, excluding: journal) else {
            errorMessage = String(localized: "Choose a name no other journal uses.")
            return
        }
        do {
            try store.rename(journal, to: name)
        } catch {
            viewContext.rollback()
            errorMessage = String(localized: "Try again.")
        }
    }

    private func setArchived(_ journal: Journal, _ isArchived: Bool) {
        do {
            try JournalStore(context: viewContext).setArchived(journal, isArchived)
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
            errorMessage = String(localized: "Try again.")
        }
    }

    private func delete(_ journal: Journal, choice: JournalDeletionChoice) {
        deletingJournal = nil
        do {
            let result = try JournalStore(context: viewContext).delete(journal, choice: choice)
            JournalChangeApplier.apply(result)
            CaptureController.shared.resetCaptureJournal()
            HapticManager.shared.entryDeleted()
        } catch {
            viewContext.rollback()
            errorMessage = String(localized: "Try again.")
        }
    }
}
