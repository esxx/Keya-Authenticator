import XCTest
@testable import Keya_Authenticator

@MainActor
final class PINAttemptTests: XCTestCase {

    private let pin = "123456"
    private let wrongPIN = "000000"
    private var attempt: PINAttempt!

    override func setUp() {
        super.setUp()
        try? KeychainManager.deletePIN()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        try? KeychainManager.savePIN(pin)
        attempt = PINAttempt(authenticationManager: AuthenticationManager())
    }

    override func tearDown() {
        attempt = nil
        try? KeychainManager.deletePIN()
        try? KeychainManager.deleteLockoutState(account: KeychainManager.pinLockoutAccount)
        super.tearDown()
    }

    private func fail(times: Int) {
        for _ in 0 ..< times {
            XCTAssertNil(attempt.submit(wrongPIN))
        }
    }

    func testWrongPINsBeforeTheWarningSayIncorrectPIN() {
        fail(times: 3)

        XCTAssertEqual(attempt.message, AuthenticationManager.AuthenticationError.invalidPIN.localizedDescription)
        XCTAssertEqual(attempt.failureCount, 3, "Every failure shakes, even with the same message")
        XCTAssertNil(attempt.lockoutSecondsRemaining)
    }

    func testLastAttemptBeforeLockoutWarns() {
        fail(times: 4)

        XCTAssertEqual(attempt.message, String(localized: "Incorrect PIN. One more wrong PIN locks entry for \(30) seconds."))
        XCTAssertNil(attempt.lockoutSecondsRemaining)
    }

    func testLockoutShowsCountdownImmediately() {
        fail(times: 5)

        let seconds = try? XCTUnwrap(attempt.lockoutSecondsRemaining)
        XCTAssertNotNil(seconds)
        XCTAssertEqual(attempt.message, AuthenticationManager.lockoutMessage(seconds: seconds ?? 0))
    }

    func testCountdownTicks() async throws {
        fail(times: 5)
        let start = try XCTUnwrap(attempt.lockoutSecondsRemaining)

        try await Task.sleep(for: .milliseconds(1300))

        let now = try XCTUnwrap(attempt.lockoutSecondsRemaining)
        XCTAssertLessThan(now, start)
        XCTAssertEqual(attempt.message, AuthenticationManager.lockoutMessage(seconds: now))
    }

    func testWarningBeforeTheLongerLockoutFollowsTheShortWait() async throws {
        try KeychainManager.saveLockoutState(
            KeychainManager.LockoutState(failedAttempts: 9, lockoutUntil: Date().addingTimeInterval(1), lastFailedAttempt: Date()),
            account: KeychainManager.pinLockoutAccount
        )
        XCTAssertTrue(attempt.showLockoutIfActive())

        try await Task.sleep(for: .milliseconds(1600))

        XCTAssertNil(attempt.lockoutSecondsRemaining)
        XCTAssertEqual(attempt.message, String(localized: "Incorrect PIN. One more wrong PIN locks entry for \(5) minutes."))
    }

    func testCountdownEndClearsTheMessageWhenNoLongerLockoutIsNext() async throws {
        try KeychainManager.saveLockoutState(
            KeychainManager.LockoutState(failedAttempts: 6, lockoutUntil: Date().addingTimeInterval(1), lastFailedAttempt: Date()),
            account: KeychainManager.pinLockoutAccount
        )
        XCTAssertTrue(attempt.showLockoutIfActive())

        try await Task.sleep(for: .milliseconds(1600))

        XCTAssertNil(attempt.message)
    }

    func testLockoutAlreadyActiveIsShownOnAppear() throws {
        try KeychainManager.saveLockoutState(
            KeychainManager.LockoutState(failedAttempts: 5, lockoutUntil: Date().addingTimeInterval(20), lastFailedAttempt: Date()),
            account: KeychainManager.pinLockoutAccount
        )

        XCTAssertTrue(attempt.showLockoutIfActive())
        XCTAssertNotNil(attempt.lockoutSecondsRemaining)
        XCTAssertNotNil(attempt.message)
    }

    func testCorrectPINIsAcceptedAndClearsTheMessage() {
        fail(times: 1)

        XCTAssertNotNil(attempt.submit(pin))
        XCTAssertNil(attempt.message)
    }
}
