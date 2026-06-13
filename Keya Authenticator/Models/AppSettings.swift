import Foundation
import SwiftUI

@Observable
final class AppSettings {
    // MARK: - Keys

    private enum Keys {
        static let hideCodesByDefault = "hideCodesByDefault"
        static let appTheme = "appTheme"
        static let biometricActivated = "biometricActivated"
        static let lockGracePeriod = "lockGracePeriod"
        static let backupNudgeCount = "backupNudgeCount"
        static let lastBackupDate = "lastBackupDate"
    }

    // MARK: - Security (Keychain-backed — tamper-resistant on jailbroken devices)

    var isAuthenticationEnabled: Bool = false {
        didSet { persistSecuritySettings() }
    }

    var useBiometricAuthentication: Bool = false {
        didSet { persistSecuritySettings() }
    }

    var securitySettingsSaveError: String?

    private var isPersisting = false

    private func persistSecuritySettings() {
        guard !isPersisting else { return }
        isPersisting = true
        defer { isPersisting = false }
        let s = KeychainManager.SecuritySettings(
            isAuthenticationEnabled: isAuthenticationEnabled,
            useBiometricAuthentication: useBiometricAuthentication,
            lockGracePeriod: lockGracePeriod
        )
        do {
            try KeychainManager.saveSecuritySettings(s)
            securitySettingsSaveError = nil
        } catch {
            let persisted = KeychainManager.loadSecuritySettings()
            isAuthenticationEnabled = persisted.isAuthenticationEnabled
            useBiometricAuthentication = persisted.useBiometricAuthentication
            lockGracePeriod = persisted.lockGracePeriod ?? 30
            securitySettingsSaveError = String(localized: "Security settings could not be saved. Please try again.")
        }
    }

    // MARK: - UI Preferences (UserDefaults-backed)

    var hideCodesByDefault: Bool = false {
        didSet { UserDefaults.standard.set(hideCodesByDefault, forKey: Keys.hideCodesByDefault) }
    }

    // MARK: - Preferences

    var appTheme: AppTheme = .auto {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: Keys.appTheme) }
    }

    var biometricActivated: Bool = false {
        didSet { UserDefaults.standard.set(biometricActivated, forKey: Keys.biometricActivated) }
    }

    var lockGracePeriod: Int = 30 {
        didSet { persistSecuritySettings() }
    }

    private static let validLockPeriods = [0, 5, 15, 30, 60]

    private static func clampLockPeriod(_ raw: Int) -> Int {
        validLockPeriods.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 30
    }

    var backupNudgeCount: Int = 0 {
        didSet { UserDefaults.standard.set(backupNudgeCount, forKey: Keys.backupNudgeCount) }
    }

    var lastBackupDate: Date? {
        didSet { UserDefaults.standard.set(lastBackupDate, forKey: Keys.lastBackupDate) }
    }

    // MARK: - Init

    init() {
        registerDefaults()
        clearStaleKeychainIfReinstalled()
        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()
        loadFromUserDefaults()
    }

    private func clearStaleKeychainIfReinstalled() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.keychainService,
            kSecAttrAccount: "app.installSentinel",
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecInteractionNotAllowed {
            return
        }

        if status == errSecItemNotFound {
            try? KeychainManager.deleteAllTokens()

            let add: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: Constants.keychainService,
                kSecAttrAccount: "app.installSentinel",
                kSecValueData: Data([1]),
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func loadFromUserDefaults() {
        let sec = KeychainManager.loadSecuritySettings()
        isAuthenticationEnabled = sec.isAuthenticationEnabled

        let ud = UserDefaults.standard
        hideCodesByDefault = ud.bool(forKey: Keys.hideCodesByDefault)
        appTheme = AppTheme(rawValue: ud.string(forKey: Keys.appTheme) ?? "") ?? .auto
        biometricActivated = ud.bool(forKey: Keys.biometricActivated)

        useBiometricAuthentication = sec.useBiometricAuthentication && biometricActivated

        if let keychainGrace = sec.lockGracePeriod {
            lockGracePeriod = AppSettings.clampLockPeriod(keychainGrace)
        } else {
            lockGracePeriod = AppSettings.clampLockPeriod(ud.object(forKey: Keys.lockGracePeriod) as? Int ?? 30)
            persistSecuritySettings()
        }

        backupNudgeCount = ud.integer(forKey: Keys.backupNudgeCount)
        lastBackupDate = ud.object(forKey: Keys.lastBackupDate) as? Date
    }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.hideCodesByDefault: false,
            Keys.appTheme: AppTheme.auto.rawValue,
            Keys.biometricActivated: false,
            Keys.lockGracePeriod: 30,
            Keys.backupNudgeCount: 0,
        ])
    }

    func resetToDefaults() {
        KeychainManager.deleteSecuritySettings()

        let keys = [
            Keys.hideCodesByDefault,
            Keys.appTheme,
            Keys.biometricActivated, Keys.lockGracePeriod, Keys.backupNudgeCount,
            Keys.lastBackupDate,
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        registerDefaults()
        loadFromUserDefaults()
    }
}

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Codable {
    case light
    case dark
    case auto

    var displayName: String {
        switch self {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        case .auto: return String(localized: "Auto")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}
