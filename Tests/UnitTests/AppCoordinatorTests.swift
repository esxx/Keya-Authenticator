import Security
import XCTest
@testable import Keya_Authenticator

final class AppCoordinatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        cleanKeychain()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
    }

    override func tearDown() {
        cleanKeychain()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
        super.tearDown()
    }

    private func cleanKeychain() {
        try? KeychainManager.deleteAllTokens()
        try? KeychainManager.deletePIN()
        KeychainManager.deleteSecuritySettings()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
    }

    // MARK: - Lock on return from background

    @MainActor
    private func makeUnlockedCoordinator() throws -> AppCoordinator {
        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: true,
                useBiometricAuthentication: false,
                lockGracePeriod: 30
            )
        )
        KeychainManager.deleteBackgroundTimestamp()
        let coordinator = AppCoordinator(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
        coordinator.determineInitialState()
        coordinator.completeUnlock()
        XCTAssertEqual(coordinator.appState, .main)
        return coordinator
    }

    @MainActor
    func testReturnFromBackground_withUnreadableTimestamp_locks() throws {
        let coordinator = try makeUnlockedCoordinator()
        coordinator.handleAppBackground()
        KeychainManager.deleteBackgroundTimestamp()
        coordinator.handleAppBecameActive()
        XCTAssertEqual(coordinator.appState, .appUnlock, "Time away is unknown, so the app must lock")
    }

    @MainActor
    func testBecomingActiveWithoutBackground_doesNotLock() throws {
        let coordinator = try makeUnlockedCoordinator()
        coordinator.handleAppBecameActive()
        XCTAssertEqual(coordinator.appState, .main, "Control Center or an alert must not lock the app")
    }

    @MainActor
    func testReturnFromBackground_withinGracePeriod_doesNotLock() throws {
        let coordinator = try makeUnlockedCoordinator()
        coordinator.handleAppBackground()
        coordinator.handleAppBecameActive()
        XCTAssertEqual(coordinator.appState, .main)
    }

    // MARK: - Reset

    @MainActor
    func testResetEverything_deletesTokensAndPIN_andOpensPINSetup() throws {
        try KeychainManager.savePIN("123456")
        let tokenStore = TokenStore()
        let secret = Data("reset-test-secret-1".utf8)
        try tokenStore.update([Token(name: "A", secret: secret), Token(name: "B", secret: secret + Data([1]))])

        let coordinator = AppCoordinator(
            tokenStore: tokenStore,
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
        try coordinator.resetEverything()

        XCTAssertEqual(coordinator.appState, .pinSetup)
        XCTAssertTrue(tokenStore.tokens.isEmpty)
        XCTAssertTrue(try KeychainManager.loadAllTokens().isEmpty)
        XCTAssertEqual(KeychainManager.pinPresence(), .notSet)
    }

    @MainActor
    func testResetEverything_keepsInstallSentinel() throws {
        _ = AppSettings()
        let sentinelQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: "app.installSentinel",
        ]
        XCTAssertEqual(SecItemCopyMatching(sentinelQuery as CFDictionary, nil), errSecSuccess)

        let tokenStore = TokenStore()
        let coordinator = AppCoordinator(
            tokenStore: tokenStore,
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
        try coordinator.resetEverything()

        XCTAssertEqual(SecItemCopyMatching(sentinelQuery as CFDictionary, nil), errSecSuccess,
                       "Reset must keep the install sentinel")
    }

    // MARK: - Pending URL on no-auth path

    func testDetermineInitialState_noAuth_consumesPendingURL() throws {
        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: nil
            )
        )

        let coordinator = AppCoordinator(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )

        let url = URL(string: "otpauth://totp/Test:user@example.com?secret=JBSWY3DPEHPK3PXP")!
        coordinator.handleIncomingURL(url)

        coordinator.determineInitialState()

        XCTAssertTrue(
            coordinator.mainContentViewModel.showingAddSheet,
            "Add sheet must open after URL-triggered cold launch when auth is disabled"
        )
        XCTAssertNotNil(
            coordinator.mainContentViewModel.pendingOTPAuthURI,
            "Pending URI must be forwarded to the add sheet"
        )
    }

    func testDetermineInitialState_noAuth_noPendingURL_doesNotOpenSheet() throws {
        try KeychainManager.savePIN("123456")
        try KeychainManager.saveSecuritySettings(
            KeychainManager.SecuritySettings(
                isAuthenticationEnabled: false,
                useBiometricAuthentication: false,
                lockGracePeriod: nil
            )
        )

        let coordinator = AppCoordinator(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )

        coordinator.determineInitialState()

        XCTAssertFalse(
            coordinator.mainContentViewModel.showingAddSheet,
            "Add sheet must not open when there is no pending URL"
        )
    }
}
