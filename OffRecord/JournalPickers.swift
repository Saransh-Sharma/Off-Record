//
//  JournalPickers.swift
//  OffRecord
//
//  The journal pickers: which journal Record and Write go into (the capture
//  sheet and an open entry), which journals Timeline shows, and which journal
//  a PDF export covers. Each one stays out of sight until there is a journal
//  besides the main one.
//

import CoreData
import SwiftUI

enum JournalFetch {
    static var sortDescriptors: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
    }

    static var activePredicate: NSPredicate {
        NSPredicate(format: "isArchived == NO")
    }
}

// MARK: - Capture

/// The journal pill in the capture sheet. Picking a journal also makes it the default for next time.
struct CaptureJournalMenu: View {
    @ObservedObject private var capture = CaptureController.shared
    @FetchRequest(sortDescriptors: JournalFetch.sortDescriptors, predicate: JournalFetch.activePredicate)
    private var journals: FetchedResults<Journal>

    var body: some View {
        if !journals.isEmpty {
            let current = capture.captureJournal
            Menu {
                Picker(selection: selection) {
                    Label(JournalNames.main, systemImage: JournalNames.defaultIconName).tag(UUID?.none)
                    ForEach(journals, id: \.objectID) { journal in
                        Label(JournalNames.displayName(for: journal), systemImage: journal.iconName ?? JournalNames.defaultIconName)
                            .tag(journal.id)
                    }
                } label: {
                    Text("Journal", comment: "Picker for the journal a recording goes into")
                }
            } label: {
                Label(JournalNames.displayName(for: current), systemImage: "books.vertical")
                    .font(OffRecordTypography.labelSmall)
                    .lineLimit(1)
                    .offRecordReadablePill(current == nil ? .neutral : .journal, horizontalPadding: 12, verticalPadding: 8)
            }
            .buttonStyle(.plain)
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .accessibilityLabel(String(localized: "Journal, \(JournalNames.displayName(for: current))", comment: "VoiceOver: the journal a recording goes into"))
            .accessibilityHint(String(localized: "Changes the journal.", comment: "VoiceOver hint for the capture journal picker"))
            .accessibilityIdentifier("capture.journalPicker")
        }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { capture.captureJournal?.id },
            set: { id in
                capture.captureJournalID = id
                JournalSelectionPreference.lastUsedJournalID = id
                HapticManager.shared.selectionChanged()
            }
        )
    }
}

// MARK: - Entry

/// The open entry's journal, as a pill that moves the entry to another journal.
/// Writing opens a new entry in the default journal, so this is also where Write picks one.
struct EntryJournalMenu: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: JournalFetch.sortDescriptors, predicate: JournalFetch.activePredicate)
    private var journals: FetchedResults<Journal>
    @State private var showsMoveError = false

    var body: some View {
        if !journals.isEmpty || entry.journal != nil {
            Menu {
                Picker(selection: selection) {
                    Label(JournalNames.main, systemImage: JournalNames.defaultIconName).tag(UUID?.none)
                    ForEach(journals, id: \.objectID) { journal in
                        Label(JournalNames.displayName(for: journal), systemImage: journal.iconName ?? JournalNames.defaultIconName)
                            .tag(journal.id)
                    }
                } label: {
                    Text("Move to Journal", comment: "Menu that moves an entry to another journal")
                }
            } label: {
                Label(JournalNames.displayName(for: entry.journal), systemImage: "books.vertical")
                    .font(OffRecordTypography.metadata)
                    .lineLimit(1)
                    .foregroundStyle(entry.journal == nil ? OffRecordColor.textSecondary : OffRecordReadableTintStyle.journal.foreground)
                    .padding(.horizontal, OffRecordSpacing.md)
                    .frame(minHeight: 32)
                    .background(entry.journal == nil ? OffRecordColor.surfacePrimary.opacity(0.68) : OffRecordReadableTintStyle.journal.fill, in: Capsule())
                    .overlay(Capsule().stroke(entry.journal == nil ? OffRecordColor.borderSoft : OffRecordReadableTintStyle.journal.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Journal, \(JournalNames.displayName(for: entry.journal))", comment: "VoiceOver: the journal this entry is in"))
            .accessibilityHint(String(localized: "Moves the entry to another journal.", comment: "VoiceOver hint for the entry journal menu"))
            .accessibilityIdentifier("entryDetail.journal")
            .alert(String(localized: "Couldn’t Move Entry"), isPresented: $showsMoveError) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text("Try again.", comment: "Message when moving an entry to another journal fails")
            }
        }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { entry.journal?.id },
            set: { id in move(to: id) }
        )
    }

    private func move(to id: UUID?) {
        let store = JournalStore(context: viewContext)
        let target = store.journal(withID: id)
        guard target?.objectID != entry.journal?.objectID else { return }
        do {
            let result = try store.move(entry, to: target)
            JournalChangeApplier.apply(result)
            JournalSelectionPreference.remember(target)
            if !CaptureController.shared.phase.isCapturing {
                CaptureController.shared.captureJournalID = target?.id
            }
            HapticManager.shared.selectionChanged()
        } catch {
            viewContext.rollback()
            showsMoveError = true
        }
    }
}

// MARK: - Timeline

/// All journals, the main journal, or one journal. Archived journals stay listed so their entries can be found.
struct TimelineJournalPicker: View {
    @Binding var scope: JournalScope
    @FetchRequest(sortDescriptors: JournalFetch.sortDescriptors)
    private var journals: FetchedResults<Journal>

    var body: some View {
        if !journals.isEmpty {
            let allJournals = Array(journals)
            Menu {
                Picker(selection: $scope) {
                    Label(JournalNames.all, systemImage: "books.vertical").tag(JournalScope.all)
                    Label(JournalNames.main, systemImage: JournalNames.defaultIconName).tag(JournalScope.main)
                    ForEach(allJournals.filter { !$0.isArchived }, id: \.objectID) { journal in
                        if let id = journal.id {
                            Label(JournalNames.displayName(for: journal), systemImage: journal.iconName ?? JournalNames.defaultIconName)
                                .tag(JournalScope.journal(id))
                        }
                    }
                } label: {
                    Text("Journal", comment: "Picker for which journal Timeline shows")
                }

                let archived = allJournals.filter(\.isArchived)
                if !archived.isEmpty {
                    Section(String(localized: "Archived", comment: "Group of archived journals in the Timeline journal picker")) {
                        Picker(selection: $scope) {
                            ForEach(archived, id: \.objectID) { journal in
                                if let id = journal.id {
                                    Label(JournalNames.displayName(for: journal), systemImage: "archivebox")
                                        .tag(JournalScope.journal(id))
                                }
                            }
                        } label: {
                            Text("Archived", comment: "Group of archived journals in the Timeline journal picker")
                        }
                        .pickerStyle(.inline)
                    }
                }
            } label: {
                HStack(spacing: OffRecordSpacing.xs) {
                    Image(systemName: "books.vertical")
                        .accessibilityHidden(true)
                    Text(JournalNames.displayName(for: scope, journals: allJournals))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(OffRecordTypography.annotation.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(OffRecordTypography.labelSmall)
                .offRecordReadablePill(scope == .all ? .neutral : .journal, horizontalPadding: 12, verticalPadding: 8)
            }
            .buttonStyle(.plain)
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(String(localized: "Journal, \(JournalNames.displayName(for: scope, journals: allJournals))", comment: "VoiceOver: which journal Timeline shows"))
            .accessibilityIdentifier("timeline.journalPicker")
            .onChange(of: journals.map(\.objectID)) { _, _ in
                // A deleted journal can't stay selected.
                if case .journal(let id) = scope, !journals.contains(where: { $0.id == id }) {
                    scope = .all
                }
            }
        }
    }
}

// MARK: - Export

/// The journal a PDF export covers.
struct ExportJournalPicker: View {
    @Binding var scope: JournalScope
    @FetchRequest(sortDescriptors: JournalFetch.sortDescriptors)
    private var journals: FetchedResults<Journal>

    var body: some View {
        if !journals.isEmpty {
            Picker(String(localized: "Journal", comment: "Export option: which journal to export"), selection: $scope) {
                Text(JournalNames.all).tag(JournalScope.all)
                Text(JournalNames.main).tag(JournalScope.main)
                ForEach(journals, id: \.objectID) { journal in
                    if let id = journal.id {
                        Text(JournalNames.displayName(for: journal)).tag(JournalScope.journal(id))
                    }
                }
            }
            .accessibilityIdentifier("settings.export.journal")
        }
    }
}
