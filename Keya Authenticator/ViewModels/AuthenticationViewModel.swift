import Foundation
import LocalAuthentication
import SwiftUI

@Observable
final class AuthenticationViewModel {
    // MARK: - Dependencies

    let authenticationManager: AuthenticationManager
    let settings: AppSettings
    let pinAttempt: PINAttempt

    // MARK: - Published Properties

    var pinText = ""
    var biometricAvailable = false
    var biometricIcon = "faceid"
    var biometricDisplayName = "Face ID"

    var errorMessage: String? {
        pinAttempt.message ?? otherMessage
    }

    private var otherMessage: String?

    // MARK: - Callbacks

    var onUnlock: (() -> Void)?
    var biometricChangedDetected = false

    // MARK: - Initialization

    init(authenticationManager: AuthenticationManager, settings: AppSettings) {
        self.authenticationManager = authenticationManager
        self.settings = settings
        pinAttempt = PINAttempt(authenticationManager: authenticationManager)
        updateBiometricStatus()
    }

    // MARK: - Biometric Status

    private func updateBiometricStatus() {
        biometricAvailable = authenticationManager.isBiometricAvailable
        biometricIcon = authenticationManager.biometricIcon
        biometricDisplayName = authenticationManager.biometricDisplayName
    }

    // MARK: - PIN Authentication

    func authenticateWithPIN() {
        guard !pinText.isEmpty else {
            otherMessage = String(localized: "Please enter your PIN")
            return
        }
        otherMessage = nil

        let result = pinAttempt.submit(pinText)
        pinText = ""
        guard let result else {
            ClipboardManager.shared.provideHapticFeedback(.error)
            return
        }
        ClipboardManager.shared.provideHapticFeedback(.success)
        if result == .successBiometricChanged {
            settings.useBiometricAuthentication = false
            settings.biometricActivated = false
            authenticationManager.clearBiometricFingerprint()
            biometricChangedDetected = true
            return
        }
        onUnlock?()
    }

    // MARK: - Biometric Authentication

    func authenticateWithBiometrics() async {
        guard biometricAvailable else {
            otherMessage = String(localized: "Biometric Unavailable")
            return
        }

        otherMessage = nil
        if pinAttempt.lockoutSecondsRemaining == nil {
            pinAttempt.clearMessage()
        }

        do {
            try await authenticationManager.authenticateWithBiometrics()
            await MainActor.run {
                onUnlock?()
            }
        } catch let error as AuthenticationManager.AuthenticationError {
            await MainActor.run {
                otherMessage = error.localizedDescription
                updateBiometricStatus()
            }
        } catch {
            await MainActor.run {
                otherMessage = String(localized: "Authentication failed")
            }
        }
    }
}
