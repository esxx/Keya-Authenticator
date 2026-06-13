import Security
import XCTest
@testable import Keya_Authenticator

final class AppSettingsTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        KeychainManager.deleteSecuritySettings()
        KeychainManager.deleteBiometricFingerprint()
        UserDefaults.standard.removeObject(forKey: "biometricActivated")
        writeInstallSentinel()
    }

    override func tearDown() {
        KeychainManager.deleteSecuritySettings()
        KeychainManager.deleteBiometricFingerprint()
        UserDefaults.standard.removeObject(forKey: "biometricActivated")
        super.tearDown()
    }

    // MARK: - Reinstall desync (regression for Face ID bug)

    func testReinstall_keychainHasBiometricTrue_userDefaultsHasNoBiometricActivated_resetsToFalse() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: true,   // ← stale Keychain value
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.removeObject(forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertFalse(
            settings.useBiometricAuthentication,
            "useBiometricAuthentication must be false when biometricActivated is absent — " +
            "stale Keychain value from before reinstall must not activate Face ID silently"
        )
        XCTAssertFalse(
            settings.biometricActivated,
            "biometricActivated must remain false (UserDefaults was wiped on reinstall)"
        )
    }

    // MARK: - Normal (non-reinstall) cases

    func testNormalLaunch_bothFlagsTrue_biometricStaysEnabled() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: true,
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.set(true, forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertTrue(settings.useBiometricAuthentication)
        XCTAssertTrue(settings.biometricActivated)
    }

    func testNormalLaunch_bothFlagsFalse_biometricStaysDisabled() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.set(false, forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertFalse(settings.useBiometricAuthentication)
        XCTAssertFalse(settings.biometricActivated)
    }

    func testOppositeDesync_keychainFalse_userDefaultsTrue_biometricOff() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: false,
                lockGracePeriod: 30
            )
        )
        UserDefaults.standard.set(true, forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertFalse(
            settings.useBiometricAuthentication,
            "AND logic: false && true must be false"
        )
    }

    // MARK: - lockGracePeriod preserved through sync

    func testReinstallDesync_lockGracePeriodPreserved() throws {
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: true,
                lockGracePeriod: 5           // non-default value
            )
        )
        UserDefaults.standard.removeObject(forKey: "biometricActivated")

        let settings = AppSettings()

        XCTAssertEqual(settings.lockGracePeriod, 5,
                       "lockGracePeriod must survive the biometric sync correction")
    }

    // MARK: - Helpers

    private func writeInstallSentinel() {
        let del: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.keychainService,
            kSecAttrAccount: "app.installSentinel",
        ]
        SecItemDelete(del as CFDictionary)
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
