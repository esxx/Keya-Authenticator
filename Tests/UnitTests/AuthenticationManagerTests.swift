import Security
import XCTest
@testable import Keya_Authenticator

final class AuthenticationManagerTests: XCTestCase {

    private var manager: AuthenticationManager!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        try? KeychainManager.deletePIN()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        manager = AuthenticationManager()
    }

    override func tearDown() {
        try? KeychainManager.deletePIN()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        manager = nil
        super.tearDown()
    }

    // MARK: - No PIN set

    func testNoPINSetThrowsNoPINSet() {
        XCTAssertThrowsError(try manager.authenticateWithPIN("123456")) { error in
            guard case AuthenticationManager.AuthenticationError.noPINSet = error else {
                return XCTFail("Expected .noPINSet, got \(error)")
            }
        }
    }

    // MARK: - Correct / wrong PIN

    func testCorrectPINSucceeds() throws {
        try KeychainManager.savePIN("123456")
        XCTAssertNoThrow(try manager.authenticateWithPIN("123456"))
    }

    func testWrongPINThrowsInvalidPIN() throws {
        try KeychainManager.savePIN("123456")
        XCTAssertThrowsError(try manager.authenticateWithPIN("000000")) { error in
            guard case AuthenticationManager.AuthenticationError.invalidPIN = error else {
                return XCTFail("Expected .invalidPIN, got \(error)")
            }
        }
    }

    // MARK: - Lockout state respected

    func testActiveHardLockoutPreventsAnyAttempt() throws {
        try KeychainManager.savePIN("123456")
        let state = KeychainManager.LockoutState(
            failedAttempts: 10,
            lockoutUntil: Date().addingTimeInterval(300),
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        XCTAssertThrowsError(try manager.authenticateWithPIN("123456")) { error in
            guard case AuthenticationManager.AuthenticationError.pinLocked(_) = error else {
                return XCTFail("Expected .pinLocked while lockout is active, got \(error)")
            }
        }
    }

    func testExpiredLockoutAllowsAttempt() throws {
        try KeychainManager.savePIN("123456")
        let state = KeychainManager.LockoutState(
            failedAttempts: 5,
            lockoutUntil: Date().addingTimeInterval(-1),
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        XCTAssertThrowsError(try manager.authenticateWithPIN("000000")) { error in
            guard case AuthenticationManager.AuthenticationError.invalidPIN = error else {
                return XCTFail("Expected .invalidPIN after expired lockout, got \(error)")
            }
        }
    }

    // MARK: - Lockout thresholds

    func testSoftLockoutEngagedAfterFiveFailures() throws {
        try KeychainManager.savePIN("123456")
        let state = KeychainManager.LockoutState(
            failedAttempts: 4,
            lockoutUntil: nil,
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        XCTAssertThrowsError(try manager.authenticateWithPIN("000000"))

        XCTAssertThrowsError(try manager.authenticateWithPIN("123456")) { error in
            guard case AuthenticationManager.AuthenticationError.pinLocked(_) = error else {
                return XCTFail("Expected .pinLocked after soft lockout, got \(error)")
            }
        }

        let saved = try KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount)
        XCTAssertNotNil(saved.lockoutUntil)
        XCTAssertGreaterThan(saved.lockoutUntil!, Date().addingTimeInterval(25),
                             "Soft lockout should be ~30 seconds from now")
    }

    func testHardLockoutEngagedAfterTenFailures() throws {
        try KeychainManager.savePIN("123456")
        let state = KeychainManager.LockoutState(
            failedAttempts: 9,
            lockoutUntil: nil,
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        XCTAssertThrowsError(try manager.authenticateWithPIN("000000"))

        let saved = try KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount)
        XCTAssertEqual(saved.failedAttempts, 10)
        XCTAssertNotNil(saved.lockoutUntil)
        XCTAssertGreaterThan(saved.lockoutUntil!, Date().addingTimeInterval(4 * 60),
                             "Hard lockout should be ~5 minutes from now")
    }

    // MARK: - Correct PIN resets counter

    func testCorrectPINResetsFailedAttemptCounter() throws {
        try KeychainManager.savePIN("123456")
        let state = KeychainManager.LockoutState(
            failedAttempts: 3,
            lockoutUntil: nil,
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        try manager.authenticateWithPIN("123456")

        let saved = try KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount)
        XCTAssertEqual(saved.failedAttempts, 0, "Successful auth must reset the attempt counter")
        XCTAssertNil(saved.lockoutUntil, "Successful auth must clear any pending lockout")
    }

    // MARK: - Corrupt lockout state

    func testCorruptLockoutStateTreatedAsHardLockout() throws {
        try KeychainManager.savePIN("123456")
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainManager.service,
            kSecAttrAccount as String: KeychainManager.pinLockoutAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainManager.service,
            kSecAttrAccount as String: KeychainManager.pinLockoutAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data([0xDE, 0xAD, 0xBE, 0xEF]),
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        XCTAssertThrowsError(try manager.authenticateWithPIN("123456")) { error in
            guard case AuthenticationManager.AuthenticationError.pinLocked(_) = error else {
                return XCTFail("Expected .pinLocked for corrupt lockout state, got \(error)")
            }
        }
    }

    // MARK: - setPIN validation

    func testSetPINMismatchThrows() {
        XCTAssertThrowsError(try manager.setPIN("123456", confirmPin: "654321"),
                             "Mismatched PINs must throw")
    }

    func testSetPINTooShortThrows() {
        XCTAssertThrowsError(try manager.setPIN("1234", confirmPin: "1234"),
                             "PIN shorter than 6 digits must throw")
    }

    func testSetPINNonNumericThrows() {
        XCTAssertThrowsError(try manager.setPIN("abc123", confirmPin: "abc123"),
                             "Non-numeric PIN must throw")
    }

    func testSetPINValid() throws {
        XCTAssertFalse(KeychainManager.isPINSet())
        try manager.setPIN("123456", confirmPin: "123456")
        XCTAssertTrue(KeychainManager.isPINSet())
    }

    // MARK: - pinLockoutSecondsRemaining

    func testLockoutSecondsRemainingNilWhenNotLocked() {
        XCTAssertNil(manager.pinLockoutSecondsRemaining())
    }

    func testLockoutSecondsRemainingPositiveWhenLocked() throws {
        let state = KeychainManager.LockoutState(
            failedAttempts: 5,
            lockoutUntil: Date().addingTimeInterval(30),
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        let remaining = manager.pinLockoutSecondsRemaining()
        XCTAssertNotNil(remaining)
        XCTAssertGreaterThan(remaining!, 0)
        XCTAssertLessThanOrEqual(remaining!, 30)
    }
}
