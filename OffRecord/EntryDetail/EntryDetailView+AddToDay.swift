//
//  EntryDetailView+AddToDay.swift
//  OffRecord
//
//  The Add section under the entry: Add Text and Add Photos.
//

import SwiftUI
import PhotosUI

extension EntryDetailView {
    var addToDaySection: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            sectionLabel(String(localized: "Add", comment: "Section header above the Add Text and Add Photos buttons."))
            HStack(spacing: OffRecordSpacing.md) {
                addTextButton
                addPhotosButton
            }
        }
    }

    private var addTextButton: some View {
        Button {
            beginNewTextBlock()
        } label: {
            Label("Add Text", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .font(OffRecordTypography.labelMedium)
        .foregroundStyle(OffRecordReadableTintStyle.brand.foreground)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .background(OffRecordReadableTintStyle.brand.fill, in: Capsule())
        .overlay(Capsule().stroke(OffRecordReadableTintStyle.brand.border, lineWidth: 1))
    }

    private var addPhotosButton: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        ) {
            Label("Add Photos", systemImage: "photo.badge.plus")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordReadableTintStyle.journal.foreground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(OffRecordReadableTintStyle.journal.fill, in: Capsule())
                .overlay(Capsule().stroke(OffRecordReadableTintStyle.journal.border, lineWidth: 1))
        }
    }
}
