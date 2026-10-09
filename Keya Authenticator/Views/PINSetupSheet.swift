import SwiftUI

struct PINSetupSheet: View {
    let mode: AppLockSettingsView.PINSetupMode
    let authenticationManager: AuthenticationManager
    @Binding var newPIN: String
    @Binding var confirmPIN: String
    @Binding var errorMessage: String?
    let onComplete: (_ success: Bool, _ biometricChanged: Bool) -> Void

    var body: some View {
        Form {
            Section {
                SecureField("New PIN", text: $newPIN)
                    .keyboardType(.numberPad)
                SecureField("Confirm", text: $confirmPIN)
                    .keyboardType(.numberPad)

                if !newPIN.isEmpty, !confirmPIN.isEmpty, newPIN != confirmPIN {
                    Text("PINs don't match")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                if !newPIN.isEmpty,
                   newPIN.count != AuthenticationManager.pinLength || !newPIN.allSatisfy(\.isNumber)
                {
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
        }
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.background)
        .navigationTitle(mode == .changeExisting ? "Change PIN" : "Set PIN")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: savePIN).disabled(isSaveDisabled)
            }
        }
    }

    // MARK: - Helpers

    private var isSaveDisabled: Bool {
        let newPINInvalid = newPIN.count != AuthenticationManager.pinLength || !newPIN.allSatisfy(\.isNumber)
        return newPIN.isEmpty || confirmPIN.isEmpty || newPIN != confirmPIN || newPINInvalid
    }

    private func savePIN() {
        guard !isSaveDisabled else { return }
        Task {
            do {
                let biometricChanged = mode == .changeExisting && authenticationManager.hasBiometricFingerprintChanged
                try authenticationManager.setPIN(
                    newPIN,
                    confirmPin: confirmPIN,
                    allowOverwrite: mode == .changeExisting
                )
                await MainActor.run {
                    onComplete(true, biometricChanged)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
