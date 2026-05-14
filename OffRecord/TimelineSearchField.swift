//
//  TimelineSearchField.swift
//  OffRecord
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct TimelineSearchField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onCancel: () -> Void

    init(
        text: Binding<String>,
        isFocused: Binding<Bool> = .constant(false),
        onCancel: @escaping () -> Void = {}
    ) {
        _text = text
        _isFocused = isFocused
        self.onCancel = onCancel
    }

    var body: some View {
        #if os(iOS)
        TimelineUIKitSearchField(text: $text, isFocused: $isFocused, onCancel: onCancel)
            .frame(height: TimelineDesign.searchHeight)
            .padding(.horizontal, 5)
            .clipped()
            .background(
                Capsule()
                    .fill(OffRecordColor.surfacePrimary.opacity(0.58))
                    .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 5)
            )
        #else
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.medium))
                .foregroundStyle(OffRecordColor.textBrand)
            TextField("Search entries", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
        }
        .padding(.horizontal, 18)
        .background(Capsule().fill(OffRecordColor.surfacePrimary.opacity(0.58)))
        #endif
    }
}

#if os(iOS)
struct TimelineUIKitSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onCancel: () -> Void

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = TimelineCompactSearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search entries"
        searchBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)
        searchBar.backgroundImage = UIImage()
        searchBar.backgroundColor = .clear
        searchBar.directionalLayoutMargins = .zero

        let searchField = searchBar.searchTextField
        searchField.textColor = UIColor(OffRecordColor.textPrimary)
        searchField.tintColor = UIColor(OffRecordColor.brandLavenderDark)
        searchField.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 17, weight: .regular)
        )
        searchField.adjustsFontForContentSizeCategory = true
        searchField.borderStyle = .none
        searchField.backgroundColor = .clear
        searchField.clearButtonMode = .whileEditing
        searchField.leftView?.tintColor = UIColor(OffRecordColor.textBrand)
        searchField.accessibilityLabel = "Search entries"
        searchField.accessibilityIdentifier = "timeline.searchField"
        searchField.accessibilityTraits.insert(.searchField)
        searchField.heightAnchor.constraint(equalToConstant: 34).isActive = true

        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        context.coordinator.onCancel = onCancel

        if uiView.text != text {
            uiView.text = text
        }

        if uiView.showsCancelButton != isFocused {
            uiView.setShowsCancelButton(isFocused, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        var onCancel: () -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, onCancel: @escaping () -> Void) {
            _text = text
            _isFocused = isFocused
            self.onCancel = onCancel
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            isFocused = true
            searchBar.setShowsCancelButton(true, animated: true)
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            isFocused = false
            searchBar.setShowsCancelButton(false, animated: true)
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            text = ""
            searchBar.text = ""
            isFocused = false
            searchBar.resignFirstResponder()
            searchBar.setShowsCancelButton(false, animated: true)
            onCancel()
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            isFocused = false
            searchBar.resignFirstResponder()
        }
    }
}

final class TimelineCompactSearchBar: UISearchBar {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: TimelineDesign.searchHeight)
    }
}
#endif
