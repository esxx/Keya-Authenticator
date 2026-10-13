import SwiftUI
import UIKit

// MARK: - Secure PIN Field

struct SecurePINField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .numberPad
        textField.isSecureTextEntry = true
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused

        if uiView.text != text {
            uiView.text = text
        }
        guard isFocused != uiView.isFirstResponder else { return }
        let focus = $isFocused
        DispatchQueue.main.async {
            if focus.wrappedValue, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !focus.wrappedValue, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        nonisolated deinit {}

        var text: Binding<String>
        var isFocused: Binding<Bool>

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        @objc func textChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if isFocused.wrappedValue {
                isFocused.wrappedValue = false
            }
        }
    }
}
