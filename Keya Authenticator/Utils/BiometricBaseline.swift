import Foundation

enum BiometricBaseline {
    static let keychainAccount = "biometric_fingerprint"

    static func hasChanged(stored: Data?, current: Data?) -> Bool {
        guard let stored else { return false }
        guard let current else { return true }
        return stored != current
    }
}
