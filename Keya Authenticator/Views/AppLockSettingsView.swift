import LocalAuthentication
import SwiftUI

struct AppLockSettingsView: View {
    @Bindable var authenticationManager: AuthenticationManager
    @Bindable var settings: AppSettings

    @State private var showingPINSetup = false
    @State private var pinSetupMode: PINSetupMode = .setNew
    @State private var showingPINVerify = false
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var pinErrorMessage: String?

    @State private var biometricErrorMessage: String?
    @State private var showingBiometricError = false

    @Environment(\.dismiss) private var dismiss

    enum PINSetupMode { case setNew, changeExisting }

    var body: some View {
        List {
            // MARK: - App Lock

            Section {
                Toggle("PIN", isOn: pinToggleBinding)
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)

                if settings.isAuthenticationEnabled, KeychainManager.isPINSet() {
                    Button("Change PIN") {
                        pinSetupMode = .changeExisting
                        showingPINSetup = true
                    }
                    .foregroundColor(.blue)
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                }
            } header: {
                Text("App lock").textCase(.uppercase)
            }

            // MARK: - Auto-lock

            if settings.isAuthenticationEnabled {
                Section {
                    Picker("Lock after", selection: $settings.lockGracePeriod) {
                        Text("Immediately").tag(0)
                        Text("5 seconds").tag(5)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                } header: {
                    Text("Auto-lock").textCase(.uppercase)
                }
            }

            // MARK: - Biometric Authentication

            if settings.isAuthenticationEnabled, authenticationManager.isBiometricAvailable {
                Section {
                    Toggle(
                        authenticationManager.biometricDisplayName,
                        isOn: biometricToggleBinding
                    )
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                } header: {
                    Text("Biometric Authentication").textCase(.uppercase)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.background)
        .navigationTitle("App lock")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Biometric Unavailable", isPresented: $showingBiometricError) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(biometricErrorMessage ?? "")
        }
        .sheet(isPresented: $showingPINSetup) {
            PINSetupSheet(
                mode: pinSetupMode,
                authenticationManager: authenticationManager,
                currentPIN: $currentPIN,
                newPIN: $newPIN,
                confirmPIN: $confirmPIN,
                errorMessage: $pinErrorMessage
            ) { success, biometricChanged in
                if success {
                    if pinSetupMode == .setNew {
                        settings.isAuthenticationEnabled = true
                    }
                    if biometricChanged {
                        settings.useBiometricAuthentication = false
                        settings.biometricActivated = false
                        authenticationManager.clearBiometricFingerprint()
                    }
                }
                showingPINSetup = false
                currentPIN = ""
                newPIN = ""
                confirmPIN = ""
                pinErrorMessage = nil
            }
        }
        .sheet(isPresented: $showingPINVerify) {
            PINVerifySheet(authenticationManager: authenticationManager) { verified in
                showingPINVerify = false
                if verified {
                    try? authenticationManager.removePIN()
                    settings.isAuthenticationEnabled = false
                }
            }
        }
    }

    // MARK: - Bindings

    private var pinToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.isAuthenticationEnabled },
            set: { newValue in
                if newValue {
                    if !KeychainManager.isPINSet() {
                        pinSetupMode = .setNew
                        showingPINSetup = true
                    } else {
                        settings.isAuthenticationEnabled = true
                    }
                } else {
                    if KeychainManager.isPINSet() {
                        showingPINVerify = true
                    } else {
                        settings.isAuthenticationEnabled = false
                    }
                }
            }
        )
    }

    private var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.useBiometricAuthentication },
            set: { newValue in
                if !newValue {
                    settings.useBiometricAuthentication = false
                    settings.biometricActivated = false
                    return
                }
                var error: NSError?
                let ctx = LAContext()
                let available = ctx.canEvaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics, error: &error
                )
                guard available else {
                    settings.useBiometricAuthentication = false
                    if let laError = error as? LAError {
                        switch laError.code {
                        case .biometryNotAvailable:
                            biometricErrorMessage = "\(Constants.appName) doesn't have permission to use \(authenticationManager.biometricDisplayName). Tap 'Open Settings' to allow it."
                        case .biometryNotEnrolled:
                            biometricErrorMessage = "\(authenticationManager.biometricDisplayName) is not set up on this device. Go to iOS Settings → \(authenticationManager.biometricDisplayName) & Passcode to enroll."
                        case .passcodeNotSet:
                            biometricErrorMessage = "A device passcode is required to use \(authenticationManager.biometricDisplayName). Set one in iOS Settings → Face ID & Passcode."
                        default:
                            biometricErrorMessage = "\(authenticationManager.biometricDisplayName) is not available right now."
                        }
                    } else {
                        biometricErrorMessage = "\(authenticationManager.biometricDisplayName) is not available right now."
                    }
                    showingBiometricError = true
                    return
                }
                Task {
                    do {
                        try await ctx.evaluatePolicy(
                            .deviceOwnerAuthenticationWithBiometrics,
                            localizedReason: "Confirm to enable \(authenticationManager.biometricDisplayName) unlock"
                        )
                        await MainActor.run {
                            settings.useBiometricAuthentication = true
                            settings.biometricActivated = true
                            authenticationManager.updateBiometricFingerprint()
                        }
                    } catch {
                        await MainActor.run {
                            settings.useBiometricAuthentication = false
                            settings.biometricActivated = false
                        }
                    }
                }
            }
        )
    }
}
