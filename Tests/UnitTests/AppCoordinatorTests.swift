import XCTest
@testable import Keya_Authenticator

final class AppCoordinatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        UserDefaults.standard.removeObject(forKey: KeychainManager.migrationV1Key)
        super.tearDown()
    }

    // MARK: - Pending URL on no-auth path

    func testDetermineInitialState_noAuth_consumesPendingURL() throws {
        _ = AppSettings()

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
        _ = AppSettings()

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
