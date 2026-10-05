import XCTest
@testable import Keya_Authenticator

@MainActor
final class BiometricChangeUnlockTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? KeychainManager.deletePIN()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        KeychainManager.deleteBiometricFingerprint()
        KeychainManager.deleteSecuritySettings()
    }

    override func tearDown() {
        try? KeychainManager.deletePIN()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        KeychainManager.deleteBiometricFingerprint()
        KeychainManager.deleteSecuritySettings()
        UserDefaults.standard.removeObject(forKey: "biometricActivated")
        super.tearDown()
    }

    func testPINUnlockAfterBiometricChangeDisablesBiometricsBeforeUnlocking() throws {
        let manager = AuthenticationManager()
        try XCTSkipUnless(manager.isBiometricAvailable, "Needs Face ID or Touch ID enrolled on the test device")

        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(isAuthenticationEnabled: true, useBiometricAuthentication: true, lockGracePeriod: 30)
        )
        UserDefaults.standard.set(true, forKey: "biometricActivated")
        KeychainManager.saveBiometricFingerprint(Data("stale-enrollment".utf8))

        let settings = AppSettings()
        XCTAssertTrue(settings.useBiometricAuthentication)
        let viewModel = AuthenticationViewModel(authenticationManager: manager, settings: settings)
        var unlocked = false
        viewModel.onUnlock = { unlocked = true }

        viewModel.pinText = "123456"
        viewModel.authenticateWithPIN()

        XCTAssertTrue(viewModel.biometricChangedDetected)
        XCTAssertFalse(settings.useBiometricAuthentication, "Biometrics must be off even if the lock screen disappears")
        XCTAssertFalse(settings.biometricActivated)
        XCTAssertNil(KeychainManager.loadBiometricFingerprint(), "The stale baseline must go, or the alert repeats on every unlock")
        XCTAssertFalse(unlocked, "Unlock waits until the user has seen the explanation")
    }
}
