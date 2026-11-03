//
//  EntryDetailView+Header.swift
//  OffRecord
//
//  The entry's top bar (back, star, the More menu, and Save and Cancel while
//  editing) and the date title with its generated title under it.
//

import SwiftUI

extension EntryDetailView {
    // MARK: - Entry Header

    var journalEntryTopBar: some View {
        ZStack {
            HStack {
                if showsDismissButton {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(OffRecordTypography.labelLarge)
                            .foregroundStyle(OffRecordColor.textBrand)
                            .frame(width: 48, height: 48)
                            .background(OffRecordColor.surfacePrimary, in: Circle())
                            .overlay(Circle().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                            .offRecordShadow(.chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("entryDetail.backButton")
                } else {
                    OffRecordIconBubble(
                        systemImage: "book.pages",
                        tint: OffRecordColor.textLavender,
                        fill: OffRecordColor.surfaceLavender,
                        size: 48,
                        iconSize: 18
                    )
                    .accessibilityHidden(true)
                }

                Spacer()

                if isActivelyEditing {
                    HStack(spacing: 8) {
                        editorToolbarButton(
                            title: String(localized: "Cancel"),
                            systemImage: "xmark.circle.fill",
                            tint: OffRecordColor.textCoral,
                            fill: OffRecordColor.surfaceBlush,
                            border: OffRecordColor.brandCoral.opacity(0.22),
                            action: cancelActiveEditing
                        )

                        editorToolbarButton(
                            title: String(localized: "Save"),
                            systemImage: "checkmark.circle.fill",
                            tint: OffRecordColor.brandSageDark,
                            fill: OffRecordColor.surfaceSage,
                            border: OffRecordColor.borderSage,
                            action: saveActiveEditing
                        )
                        .accessibilityIdentifier("entryDetail.saveText")
                        .disabled(!canSaveActiveEditing)
                        .opacity(canSaveActiveEditing ? 1 : 0.46)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(action: toggleStar) {
                            Image(systemName: entry.isStarred ? "star.fill" : "star")
                                .font(OffRecordTypography.titleSmall)
                                .foregroundStyle(entry.isStarred ? OffRecordColor.textYellow : OffRecordColor.textBrand)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: entry.isStarred)
                                .frame(width: 48, height: 48)
                                .background(OffRecordColor.surfacePrimary, in: Circle())
                                .overlay(Circle().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.isStarred ? "Unstar" : "Star")

                        Menu {
                            Button {
                                showMoodPicker = true
                            } label: {
                                Label(selectedMood == .none ? "Add Mood" : "Change Mood", systemImage: "face.smiling")
                            }
                            if !text.isEmpty {
                                Button {
                                    UIPasteboard.general.string = text
                                } label: {
                                    Label("Copy Text", systemImage: "doc.on.doc")
                                }
                            }
                            EntryAIExclusionMenuItems(entry: entry)
                            Divider()
                            Button(role: .destructive) {
                                showDeleteDayConfirm = true
                            } label: {
                                Label("Delete Entry", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(OffRecordTypography.titleSmall)
                                .foregroundStyle(OffRecordColor.textBrand)
                                .frame(width: 48, height: 48)
                                .background(OffRecordColor.surfacePrimary, in: Circle())
                                .overlay(Circle().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                        }
                        .accessibilityLabel(Text("More", comment: "Accessibility label for the menu with more actions for this entry."))
                    }
                    .offRecordShadow(.chip)
                }
            }
        }
    }

    var detailDateTitle: some View {
        VStack(spacing: 8) {
            Text(formattedShortDate)
                .font(OffRecordTypography.titleLarge)
                .foregroundStyle(OffRecordColor.textHeading)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // A generated title only when one passed validation; otherwise the date stands alone.
            if let title = entryTitles.title(for: entry) {
                Text(title)
                    .font(OffRecordTypography.bodyLarge)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityIdentifier("entryDetail.title")
            }

            HStack(spacing: 8) {
                Rectangle()
                    .fill(OffRecordColor.divider)
                    .frame(width: 58, height: 1)
                Image(systemName: "sparkle")
                    .font(OffRecordTypography.annotation)
                    .foregroundStyle(OffRecordColor.brandLavender.opacity(0.76))
                Rectangle()
                    .fill(OffRecordColor.divider)
                    .frame(width: 58, height: 1)
            }
            .accessibilityHidden(true)
        }
        .padding(.top, -4)
    }

    private func editorToolbarButton(
        title: String,
        systemImage: String,
        tint: Color,
        fill: Color,
        border: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(OffRecordTypography.labelSmall)
            } icon: {
                Image(systemName: systemImage)
                    .font(OffRecordTypography.labelMedium)
                    .symbolRenderingMode(.hierarchical)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var formattedShortDate: String {
        EntryDetailDateFormatters.shortDate.string(from: entry.date ?? Date())
    }

    private func toggleStar() {
        entry.isStarred.toggle()
        entry.updatedAt = Date()
        HapticManager.shared.entryStarred()
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        } catch {
            // ignore
        }
    }
}
