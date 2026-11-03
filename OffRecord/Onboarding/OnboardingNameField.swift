//
//  OnboardingNameField.swift
//  OffRecord
//
//  The optional name field on the welcome page, a UIKit text field with
//  inset text.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingNameField: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = InsetTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.text = text
        textField.placeholder = String(localized: "Your name (optional)")
        textField.textColor = UIColor(OffRecordColor.textPrimary)
        textField.tintColor = UIColor(OffRecordColor.textCoral)
        textField.font = UIFont.preferredFont(forTextStyle: .headline)
        textField.textContentType = .givenName
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.backgroundColor = UIColor(OffRecordColor.surfacePrimary)
        textField.layer.cornerRadius = 14
        textField.layer.masksToBounds = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.accessibilityIdentifier = "onboarding.welcome.nameField"
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: 56)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private final class InsetTextField: UITextField {
    private let contentInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: contentInsets)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: contentInsets)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: contentInsets)
    }

    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        super.clearButtonRect(forBounds: bounds).offsetBy(dx: -contentInsets.right / 2, dy: 0)
    }
}
