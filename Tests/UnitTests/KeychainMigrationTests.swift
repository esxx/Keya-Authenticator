import Security
import XCTest
@testable import Keya_Authenticator

final class KeychainMigrationTests: XCTestCase {

    // MARK: - Helpers

    private let migrationSentinelKey = KeychainManager.migrationV1Key

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: migrationSentinelKey)
        try? KeychainManager.deleteAllTokens()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: migrationSentinelKey)
        try? KeychainManager.deleteAllTokens()
        super.tearDown()
    }

    private func makeToken(name: String = "Test Token") -> Token {
        var secret = Data(name.utf8)
        while secret.count < 20 { secret.append(0xEF) }
        return Token(
            name: name,
            issuer: "Example",
            secret: secret,
            algorithm: .sha1,
            digits: 6,
            type: .totp,
            period: 30
        )
    }

    // MARK: - Round-trip

    func testMigration_allTokensSurviveIntact() throws {
        let token1 = makeToken(name: "Token A")
        let token2 = makeToken(name: "Token B")
        try KeychainManager.saveToken(token1)
        try KeychainManager.saveToken(token2)

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        let loaded = try KeychainManager.loadAllTokens()
        XCTAssertEqual(loaded.count, 2, "Both tokens must survive migration")

        let names = Set(loaded.map { $0.name })
        XCTAssertTrue(names.contains("Token A"), "Token A must survive migration")
        XCTAssertTrue(names.contains("Token B"), "Token B must survive migration")
    }

    func testMigration_tokenSecretRoundTripsCorrectly() throws {
        let original = makeToken()
        try KeychainManager.saveToken(original)

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        let loaded = try KeychainManager.loadAllTokens()
        XCTAssertEqual(loaded.count, 1, "Exactly one token must survive")
        let migrated = try XCTUnwrap(loaded.first)
        XCTAssertEqual(
            migrated.secret, original.secret,
            "Secret must be byte-for-byte identical after migration"
        )
    }

    // MARK: - Idempotency

    func testMigration_idempotent() throws {
        let token = makeToken()
        try KeychainManager.saveToken(token)

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()
        let countAfterFirst = try KeychainManager.loadAllTokens().count

        UserDefaults.standard.removeObject(forKey: migrationSentinelKey)
        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()
        let countAfterSecond = try KeychainManager.loadAllTokens().count

        XCTAssertEqual(countAfterFirst, countAfterSecond, "Token count must not change on second migration")
        XCTAssertEqual(countAfterSecond, 1, "Exactly one token must remain")
    }

    // MARK: - Sentinel behaviour

    func testMigration_sentinelWrittenOnSuccess() {
        let token = makeToken()
        try? KeychainManager.saveToken(token)

        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: migrationSentinelKey),
            "Sentinel must be absent before migration"
        )

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: migrationSentinelKey),
            "Sentinel must be set after successful migration"
        )
    }

    func testMigration_skippedWhenSentinelPresent() throws {
        let token = makeToken()
        try KeychainManager.saveToken(token)

        UserDefaults.standard.set(true, forKey: migrationSentinelKey)

        try KeychainManager.deleteAllTokens()

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        let loaded = try KeychainManager.loadAllTokens()
        XCTAssertEqual(loaded.count, 0,
                       "Migration must be skipped when sentinel is already set — " +
                       "running it would have found 0 tokens and left the store empty")
    }

    // MARK: - Empty store

    func testMigration_emptyStore_succeedsAndWritesSentinel() {
        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: migrationSentinelKey),
            "Sentinel must be written even when the store is empty"
        )
    }

    // MARK: - OTP correctness after migration

    func testMigration_otpCodeGeneratesAfterMigration() throws {
        let original = makeToken()
        try KeychainManager.saveToken(original)

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        let loaded = try XCTUnwrap(try KeychainManager.loadAllTokens().first)

        let referenceTime = Date(timeIntervalSince1970: 1_700_000_000)
        let codeFromOriginal = try original.generateCode(time: referenceTime)
        let codeFromMigrated = try loaded.generateCode(time: referenceTime)

        XCTAssertEqual(
            codeFromOriginal, codeFromMigrated,
            "Migrated token must generate the same OTP code as the original"
        )
        XCTAssertFalse(codeFromMigrated.isEmpty, "Generated code must not be empty")
        XCTAssertEqual(codeFromMigrated.count, 6, "Default TOTP code must be 6 digits")
    }
}
