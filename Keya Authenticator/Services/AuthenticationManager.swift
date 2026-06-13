import Combine
import LocalAuthentication
import SwiftUI

@Observable
final class AuthenticationManager {
    // MARK: - Biometric Info

    var isBiometricAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    var biometricDisplayName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    var biometricIcon: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "faceid" : "touchid"
    }

    // MARK: - System Biometric Lockout Check

    var isSystemBiometricLockedOut: Bool {
        let ctx = LAContext()
        var err: NSError?
        if !ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
           let laErr = err as? LAError, laErr.code == .biometryLockout { return true }
        return false
    }

    // MARK: - Biometric Fingerprint Tracking

    private func currentBiometricDomainState() -> Data? {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        return ctx.domainState.biometry.stateHash
    }

    var hasBiometricFingerprintChanged: Bool {
        guard let current = currentBiometricDomainState(),
              let stored = KeychainManager.loadBiometricFingerprint() else { return false }
        return stored != current
    }

    func updateBiometricFingerprint() {
        guard let fp = currentBiometricDomainState() else { return }
        KeychainManager.saveBiometricFingerprint(fp)
    }

    func saveCurrentBiometricBaselineIfNeeded() {
        guard KeychainManager.loadBiometricFingerprint() == nil,
              let fp = currentBiometricDomainState() else { return }
        KeychainManager.saveBiometricFingerprint(fp)
    }

    func clearBiometricFingerprint() {
        KeychainManager.deleteBiometricFingerprint()
    }

    // MARK: - Biometric Authentication

    func authenticateWithBiometrics() async throws {
        if isSystemBiometricLockedOut {
            throw AuthenticationError.biometricLockedWithGuidance
        }
        if hasBiometricFingerprintChanged {
            throw AuthenticationError.biometricFingerprintChanged
        }

        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your 2FA tokens"
            )
            if success {
            } else {
                throw AuthenticationError.biometricFailed
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel:
                throw AuthenticationError.userCancelled
            case .biometryLockout:
                throw AuthenticationError.biometricLockedWithGuidance
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                throw AuthenticationError.biometricNotAvailable
            default:
                throw AuthenticationError.biometricFailed
            }
        } catch {
            throw AuthenticationError.biometricFailed
        }
    }

    // MARK: - PIN Lockout Constants

    private static let softLockoutThreshold = 5 // attempts before 30-second cooldown
    private static let hardLockoutThreshold = 10 // attempts before 5-minute lockout
    private static let softLockoutDuration: TimeInterval = 30
    private static let hardLockoutDuration: TimeInterval = 5 * 60

    // MARK: - PIN Authentication

    // MARK: - PIN Auth Result

    enum PINAuthResult {
        case success
        case successBiometricChanged
    }

    @discardableResult
    func authenticateWithPIN(_ pin: String) throws -> PINAuthResult {
        var state = try KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount)
        if let lockedUntil = state.lockoutUntil, lockedUntil > Date() {
            throw AuthenticationError.pinLocked(until: lockedUntil)
        }

        guard let result = try KeychainManager.verifyPIN(pin) else {
            throw AuthenticationError.noPINSet
        }

        if result {
            state = KeychainManager.LockoutState(failedAttempts: 0, lockoutUntil: nil, lastFailedAttempt: nil)
            try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

            if hasBiometricFingerprintChanged {
                return .successBiometricChanged
            }
            updateBiometricFingerprint()
            return .success
        } else {
            state.failedAttempts += 1
            state.lastFailedAttempt = Date()
            if state.failedAttempts >= Self.hardLockoutThreshold {
                state.lockoutUntil = Date().addingTimeInterval(Self.hardLockoutDuration)
            } else if state.failedAttempts >= Self.softLockoutThreshold {
                state.lockoutUntil = Date().addingTimeInterval(Self.softLockoutDuration)
            }
            try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)
            throw AuthenticationError.invalidPIN
        }
    }

    func pinLockoutSecondsRemaining() -> Int? {
        guard let state = try? KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount),
              let lockedUntil = state.lockoutUntil,
              lockedUntil > Date() else { return nil }
        return max(0, Int(lockedUntil.timeIntervalSinceNow.rounded(.toNearestOrAwayFromZero)))
    }

    func setPIN(_ pin: String, confirmPin: String) throws {
        guard pin == confirmPin else { throw AuthenticationError.invalidPIN }
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { throw AuthenticationError.invalidPIN }
        try KeychainManager.savePIN(pin)
        saveCurrentBiometricBaselineIfNeeded()
    }

    func removePIN() throws {
        try KeychainManager.deletePIN()
    }

    // MARK: - Full Reset

    func performReset(tokenStore: TokenStore, settings: AppSettings) {
        tokenStore.deleteAll()
        try? removePIN()
        clearBiometricFingerprint()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        try? KeychainManager.deleteLockoutState(account: KeychainManager.biometricLockoutAccount)
        settings.resetToDefaults()
    }

    // MARK: - Lockout Message

    static func lockoutMessage(seconds: Int) -> String {
        if seconds >= 60 {
            return String(localized: "Too many attempts. Try again in \(seconds / 60)m \(seconds % 60)s.")
        } else {
            return String(localized: "Too many attempts. Try again in \(seconds)s.")
        }
    }

    // MARK: - Error Types

    enum AuthenticationError: Error {
        case invalidPIN
        case noPINSet
        case pinLocked(until: Date)
        case biometricFailed
        case biometricNotAvailable
        case biometricLockedWithGuidance
        case biometricFingerprintChanged
        case userCancelled
    }
}

// MARK: - Error Descriptions

extension AuthenticationManager.AuthenticationError {
    var localizedDescription: String {
        switch self {
        case .invalidPIN:
            return "Incorrect PIN"
        case .noPINSet:
            return "No PIN is set"
        case let .pinLocked(until):
            let seconds = Int(until.timeIntervalSinceNow.rounded(.up))
            return AuthenticationManager.lockoutMessage(seconds: max(0, seconds))
        case .biometricFailed:
            return "Biometric authentication failed"
        case .biometricNotAvailable:
            return "Biometric authentication is not available"
        case .biometricLockedWithGuidance:
            return "Biometric authentication is locked. Please unlock your device with your passcode and try again."
        case .biometricFingerprintChanged:
            return "Biometric database changed. Please authenticate with PIN first."
        case .userCancelled:
            return "Authentication cancelled"
        }
    }
}
