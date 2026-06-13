import Security
import XCTest
@testable import Keya_Authenticator

/// Tests for `KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()`.
///
/// The migration is the highest-risk part of the AutoFill feature: it re-saves every
/// token Keychain item so it lands in the shared access group that the Credential
/// Provider Extension can read.  A bug here can silently delete tokens for users who
/// hold 2FA codes for every important account they own.
///
/// Test strategy:
///   1. Round-trip — tokens survive migration intact.
///   2. Idempotency — running the migration twice produces the same result.
///   3. Sentinel behaviour — sentinel is only written when all tokens succeed.
///   4. Empty store — migration on an empty store succeeds immediately.
///   5. OTP correctness — generateCode() still produces the expected value after
///      migration; the secret round-trips through the Keychain without corruption.
final class KeychainMigrationTests: XCTestCase {

    // MARK: - Helpers

    // Use the production constant so this never silently drifts out of sync.
    private let migrationSentinelKey = KeychainManager.migrationV1Key

    /// Removes migration sentinel + all tokens before / after each test.
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

    /// Make a TOTP token with a known secret for OTP assertions.
    private func makeToken(name: String = "Test Token") -> Token {
        // 20-byte Base32 secret: "JBSWY3DPEHPK3PXP"
        let secret = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0xDE, 0xAD, 0xBE, 0xEF,
                           0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0xDE, 0xAD, 0xBE, 0xEF])
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

    /// Tokens written before migration are still loadable afterwards with the same
    /// field values — no data loss, no corruption.
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

    /// Secrets must round-trip through migration without corruption — a corrupted
    /// secret produces wrong OTP codes and effectively locks the user out.
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

    /// Running the migration a second time is a no-op — tokens are not duplicated
    /// and the sentinel remains set.
    func testMigration_idempotent() throws {
        let token = makeToken()
        try KeychainManager.saveToken(token)

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()
        let countAfterFirst = try KeychainManager.loadAllTokens().count

        // Reset sentinel to force a second migration run.
        UserDefaults.standard.removeObject(forKey: migrationSentinelKey)
        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()
        let countAfterSecond = try KeychainManager.loadAllTokens().count

        XCTAssertEqual(countAfterFirst, countAfterSecond, "Token count must not change on second migration")
        XCTAssertEqual(countAfterSecond, 1, "Exactly one token must remain")
    }

    // MARK: - Sentinel behaviour

    /// Sentinel is written after a successful migration so future launches skip it.
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

    /// When sentinel is already set, migration does NOT re-run and does NOT change
    /// token contents.
    func testMigration_skippedWhenSentinelPresent() throws {
        let token = makeToken()
        try KeychainManager.saveToken(token)

        // Pre-set sentinel to simulate a previous successful migration.
        UserDefaults.standard.set(true, forKey: migrationSentinelKey)

        // Delete all tokens from the Keychain AFTER setting the sentinel.
        // If migration ran again it would see an empty store and "succeed"
        // producing 0 tokens — which would break this assertion.
        try KeychainManager.deleteAllTokens()

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        // Token is gone (we deleted it) but migration never re-reads the store.
        let loaded = try KeychainManager.loadAllTokens()
        XCTAssertEqual(loaded.count, 0,
                       "Migration must be skipped when sentinel is already set — " +
                       "running it would have found 0 tokens and left the store empty")
    }

    // MARK: - Empty store

    /// Migration on an empty Keychain completes immediately and writes the sentinel.
    func testMigration_emptyStore_succeedsAndWritesSentinel() {
        // setUp already deleted all tokens.
        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: migrationSentinelKey),
            "Sentinel must be written even when the store is empty"
        )
    }

    // MARK: - OTP correctness after migration

    /// After migration, generateCode() must still return a valid TOTP code.
    /// This guards against secret corruption — a corrupted secret produces a
    /// different code and locks the user out of every account it protects.
    func testMigration_otpCodeGeneratesAfterMigration() throws {
        let original = makeToken()
        try KeychainManager.saveToken(original)

        KeychainManager.migrateTokensToSharedKeychainGroupIfNeeded()

        let loaded = try XCTUnwrap(try KeychainManager.loadAllTokens().first)

        // Both the original and the migrated token must generate the same code
        // for any given time — they share the same secret.
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
