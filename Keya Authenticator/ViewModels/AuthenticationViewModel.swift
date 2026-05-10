import Foundation
import LocalAuthentication
import SwiftUI

@Observable
final class AuthenticationViewModel {
    // MARK: - Dependencies

    let authenticationManager: AuthenticationManager
    let settings: AppSettings

    // MARK: - Published Properties

    var pinText = ""
    var errorMessage: String?
    var isAuthenticating = false
    var biometricAvailable = false
    var biometricIcon = "faceid"
    var biometricDisplayName = "Face ID"
    var pinLockoutSecondsRemaining: Int?

    // MARK: - Callbacks

    var onUnlock: (() -> Void)?
    var biometricChangedDetected = false

    private var lockoutTimer: Timer?

    // MARK: - Initialization

    init(authenticationManager: AuthenticationManager, settings: AppSettings) {
        self.authenticationManager = authenticationManager
        self.settings = settings
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
            errorMessage = String(localized: "Please enter your PIN")
            return
        }

        isAuthenticating = true
        errorMessage = nil

        pinLockoutSecondsRemaining = authenticationManager.pinLockoutSecondsRemaining()
        if let seconds = pinLockoutSecondsRemaining, seconds > 0 {
            errorMessage = AuthenticationManager.lockoutMessage(seconds: seconds)
            isAuthenticating = false
            pinText = ""
            startLockoutCountdown()
            return
        }

        do {
            let result = try authenticationManager.authenticateWithPIN(pinText)
            pinText = ""
            ClipboardManager.shared.provideHapticFeedback(.success)
            if result == .successBiometricChanged {
                biometricChangedDetected = true
            }
            onUnlock?()
        } catch let error as AuthenticationManager.AuthenticationError {
            errorMessage = error.localizedDescription
            pinText = ""
            ClipboardManager.shared.provideHapticFeedback(.error)
        } catch {
            errorMessage = String(localized: "Authentication failed")
            pinText = ""
            ClipboardManager.shared.provideHapticFeedback(.error)
        }

        isAuthenticating = false
    }

    // MARK: - Biometric Authentication

    func authenticateWithBiometrics() async {
        guard biometricAvailable else {
            errorMessage = String(localized: "Biometric Unavailable")
            return
        }

        isAuthenticating = true
        errorMessage = nil

        do {
            try await authenticationManager.authenticateWithBiometrics()
            await MainActor.run {
                onUnlock?()
            }
        } catch let error as AuthenticationManager.AuthenticationError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                updateBiometricStatus()
            }
        } catch {
            await MainActor.run {
                errorMessage = String(localized: "Authentication failed")
            }
        }

        await MainActor.run {
            isAuthenticating = false
        }
    }

    // MARK: - Lockout

    func checkLockoutOnAppear() {
        guard let seconds = authenticationManager.pinLockoutSecondsRemaining(), seconds > 0 else { return }
        pinLockoutSecondsRemaining = seconds
        errorMessage = AuthenticationManager.lockoutMessage(seconds: seconds)
        startLockoutCountdown()
    }

    // MARK: - Lockout Timer

    private func startLockoutCountdown() {
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let seconds = pinLockoutSecondsRemaining, seconds > 0 else {
                stopLockoutTimer()
                return
            }
            let remaining = seconds - 1
            if remaining > 0 {
                pinLockoutSecondsRemaining = remaining
                errorMessage = AuthenticationManager.lockoutMessage(seconds: remaining)
            } else {
                pinLockoutSecondsRemaining = nil
                errorMessage = nil
            }
        }
    }

    private func stopLockoutTimer() {
        lockoutTimer?.invalidate()
        lockoutTimer = nil
    }

    // MARK: - Reset

    func reset() {
        stopLockoutTimer()
        pinText = ""
        errorMessage = nil
        isAuthenticating = false
        updateBiometricStatus()
        let seconds = authenticationManager.pinLockoutSecondsRemaining()
        pinLockoutSecondsRemaining = seconds
        if let s = seconds, s > 0 {
            errorMessage = AuthenticationManager.lockoutMessage(seconds: s)
            startLockoutCountdown()
        }
    }

    // MARK: - PIN Input

    func appendToPIN(_ digit: String) {
        guard pinText.count < 6 else { return }
        pinText += digit
    }

    func removeLastPINDigit() {
        guard !pinText.isEmpty else { return }
        pinText.removeLast()
    }

    func clearPIN() {
        pinText = ""
    }
}
