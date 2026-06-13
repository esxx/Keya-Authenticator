import SwiftUI

struct PINSetupSheet: View {
    let mode: AppLockSettingsView.PINSetupMode
    let authenticationManager: AuthenticationManager
    @Binding var currentPIN: String
    @Binding var newPIN: String
    @Binding var confirmPIN: String
    @Binding var errorMessage: String?
    /// Called when the sheet finishes.
    /// - `success`: PIN was saved successfully.
    /// - `biometricChanged`: the verification step detected a biometric database change.
    let onComplete: (_ success: Bool, _ biometricChanged: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if mode == .changeExisting {
                        SecureField("Current PIN", text: $currentPIN)
                            .keyboardType(.numberPad)
                    }
                    SecureField("New PIN", text: $newPIN)
                        .keyboardType(.numberPad)
                    SecureField("Confirm", text: $confirmPIN)
                        .keyboardType(.numberPad)

                    if !newPIN.isEmpty, !confirmPIN.isEmpty, newPIN != confirmPIN {
                        Text("PINs don't match")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if !newPIN.isEmpty, newPIN.count < 6 || !newPIN.allSatisfy(\.isNumber) {
                        Text("PIN must be 6 digits")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text(mode == .changeExisting ? "Change PIN" : "Set PIN").textCase(.uppercase)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: savePIN) {
                        Text("Save")
                    }
                    .disabled(isSaveDisabled)
                    .foregroundColor(isSaveDisabled ? .gray : .blue)

                    Button("Cancel", role: .cancel) {
                        onComplete(false, false)
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Constants.Colors.background)
            .navigationTitle(mode == .changeExisting ? "Change PIN" : "Set PIN")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helpers

    private var isSaveDisabled: Bool {
        let newPINInvalid = newPIN.count != 6 || !newPIN.allSatisfy(\.isNumber)
        if mode == .changeExisting {
            return currentPIN.isEmpty || newPIN.isEmpty || confirmPIN.isEmpty
                || newPIN != confirmPIN || newPINInvalid
        }
        return newPIN.isEmpty || confirmPIN.isEmpty || newPIN != confirmPIN || newPINInvalid
    }

    private func savePIN() {
        guard !isSaveDisabled else { return }
        Task {
            do {
                var biometricChanged = false
                if mode == .changeExisting {
                    let result = try authenticationManager.authenticateWithPIN(currentPIN)
                    biometricChanged = (result == .successBiometricChanged)
                }
                try authenticationManager.setPIN(newPIN, confirmPin: confirmPIN)
                await MainActor.run {
                    onComplete(true, biometricChanged)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
