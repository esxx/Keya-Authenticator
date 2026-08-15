import XCTest
@testable import Keya_Authenticator

final class AddTokenViewModelTests: XCTestCase {

    private var tokenStore: TokenStore!
    private var settings: AppSettings!
    private var viewModel: AddTokenViewModel!

    private let validSecret = "JBSWY3DPEHPK3PXP"

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        tokenStore = TokenStore()
        settings = AppSettings()
        viewModel = AddTokenViewModel(tokenStore: tokenStore, settings: settings)
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        tokenStore = nil
        settings = nil
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func fillValidTOTP() {
        viewModel.name = "Test Token"
        viewModel.secret = validSecret
        viewModel.tokenType = .totp
        viewModel.period = 30
        viewModel.digits = 6
    }

    // MARK: - Happy path

    func testCreateValidTOTPSucceeds() {
        fillValidTOTP()
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage, "Valid TOTP input must not produce an error")
        XCTAssertEqual(tokenStore.tokens.count, 1)
    }

    func testCreateValidHOTPSucceeds() {
        viewModel.name = "HOTP Token"
        viewModel.secret = validSecret
        viewModel.tokenType = .hotp
        viewModel.counter = 0
        viewModel.digits = 6
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage, "Valid HOTP input must not produce an error")
        XCTAssertEqual(tokenStore.tokens.count, 1)
    }

    // MARK: - Name validation

    func testEmptyNameFails() {
        fillValidTOTP()
        viewModel.name = ""
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(tokenStore.tokens.count, 0)
    }

    func testWhitespaceOnlyNameFails() {
        fillValidTOTP()
        viewModel.name = "   "
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(tokenStore.tokens.count, 0)
    }

    // MARK: - Secret validation

    func testEmptySecretFails() {
        fillValidTOTP()
        viewModel.secret = ""
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testInvalidBase32SecretFails() {
        fillValidTOTP()
        viewModel.secret = "not-valid-base32!@#"
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSecretTooShortFails() {
        fillValidTOTP()
        viewModel.secret = "JBSWY3DP"
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(
            viewModel.errorMessage?.contains("10 bytes") == true,
            "Error should mention the 10-byte minimum"
        )
    }

    func testSecretAtMinimumLengthSucceeds() {
        fillValidTOTP()
        viewModel.secret = validSecret
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage, "A 10-byte secret is valid")
    }

    // MARK: - Digits validation

    func testSevenDigitsFails() {
        fillValidTOTP()
        viewModel.digits = 7
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage, "Only 6 or 8 digits are allowed")
    }

    func testSixDigitsSucceeds() {
        fillValidTOTP()
        viewModel.digits = 6
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage)
    }

    func testEightDigitsSucceeds() {
        fillValidTOTP()
        viewModel.digits = 8
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Period validation (TOTP only)

    func testTOTPPeriodBelowMinimumFails() {
        fillValidTOTP()
        viewModel.tokenType = .totp
        viewModel.period = 10
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(
            viewModel.errorMessage?.contains("Period") == true ||
            viewModel.errorMessage?.contains("period") == true
        )
    }

    func testTOTPPeriodAboveMaximumFails() {
        fillValidTOTP()
        viewModel.tokenType = .totp
        viewModel.period = 301
        viewModel.createToken()
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testTOTPPeriodAtMinimumBoundSucceeds() {
        fillValidTOTP()
        viewModel.tokenType = .totp
        viewModel.period = 15
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage, "Period == 15 is the minimum valid value")
    }

    func testTOTPPeriodAtMaximumBoundSucceeds() {
        fillValidTOTP()
        viewModel.tokenType = .totp
        viewModel.period = 300
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage, "Period == 300 is the maximum valid value")
    }

    func testHOTPIgnoresPeriodValidation() {
        fillValidTOTP()
        viewModel.tokenType = .hotp
        viewModel.period = 0
        viewModel.createToken()
        XCTAssertNil(viewModel.errorMessage,
                     "HOTP must not validate the period field")
        XCTAssertEqual(tokenStore.tokens.count, 1)
    }

    // MARK: - Field persistence after successful create

    func testFormResetsAfterSuccessfulCreate() {
        fillValidTOTP()
        viewModel.createToken()
        XCTAssertTrue(viewModel.name.isEmpty, "Form name should reset after create")
        XCTAssertTrue(viewModel.secret.isEmpty, "Form secret should reset after create")
    }

    func testShouldDismissSetAfterSuccessfulCreate() {
        fillValidTOTP()
        viewModel.createToken()
        XCTAssertTrue(viewModel.shouldDismiss, "shouldDismiss should be true after create")
    }

    // MARK: - Token fields written correctly

    func testCreatedTokenHasCorrectFields() {
        viewModel.name = "My Token"
        viewModel.issuer = "Corp"
        viewModel.secret = validSecret
        viewModel.tokenType = .totp
        viewModel.period = 60
        viewModel.digits = 8
        viewModel.algorithm = .sha256
        viewModel.createToken()

        XCTAssertEqual(tokenStore.tokens.first?.name, "My Token")
        XCTAssertEqual(tokenStore.tokens.first?.issuer, "Corp")
        XCTAssertEqual(tokenStore.tokens.first?.period, 60)
        XCTAssertEqual(tokenStore.tokens.first?.digits, 8)
        XCTAssertEqual(tokenStore.tokens.first?.algorithm, .sha256)
    }

    func testEmptyIssuerStoredAsNil() {
        fillValidTOTP()
        viewModel.issuer = ""
        viewModel.createToken()
        XCTAssertNil(tokenStore.tokens.first?.issuer, "Empty issuer string must be stored as nil")
    }

    // MARK: - handleScannedQR digit and period clamping

    func testHandleScannedQR_invalidDigits_clampsToSix() {
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)&digits=7"
        viewModel.handleScannedQR(uri)
        XCTAssertEqual(tokenStore.tokens.first?.digits, 6,
                       "digits=7 must be clamped to 6")
    }

    func testHandleScannedQR_eightDigitsPreserved() {
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)&digits=8"
        viewModel.handleScannedQR(uri)
        XCTAssertEqual(tokenStore.tokens.first?.digits, 8,
                       "digits=8 is valid and must be stored unchanged")
    }

    func testHandleScannedQR_belowMinPeriod_clampsToThirty() {
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)&period=5"
        viewModel.handleScannedQR(uri)
        XCTAssertEqual(tokenStore.tokens.first?.period, 30,
                       "period=5 is below minimum 15 — must be clamped to 30")
    }

    func testHandleScannedQR_aboveMaxPeriod_clampsToThirty() {
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)&period=600"
        viewModel.handleScannedQR(uri)
        XCTAssertEqual(tokenStore.tokens.first?.period, 30,
                       "period=600 is above maximum 300 — must be clamped to 30")
    }

    func testHandleScannedQR_validPeriod_preserved() {
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)&period=60"
        viewModel.handleScannedQR(uri)
        XCTAssertEqual(tokenStore.tokens.first?.period, 60,
                       "period=60 is valid and must be stored unchanged")
    }

    // MARK: - Duplicate confirmation (manual create)

    private func addExistingToken(name: String = "Existing") -> Token {
        let token = Token(name: name, issuer: nil, secret: validSecret.base32DecodedData!,
                          algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try? tokenStore.update([token])
        return token
    }

    func testCreateTokenWithDuplicateContentDoesNotPersistImmediately() {
        let existing = addExistingToken(name: "GitHub")
        fillValidTOTP()
        viewModel.name = "GitHub (rescanned)"

        viewModel.createToken()

        XCTAssertEqual(tokenStore.tokens.count, 1, "The duplicate must not be persisted before confirmation")
        XCTAssertEqual(tokenStore.tokens.first?.id, existing.id)
        XCTAssertNil(viewModel.errorMessage, "A duplicate is not an error")
        XCTAssertFalse(viewModel.shouldDismiss, "Sheet must stay open until the user decides")
    }

    func testCreateTokenWithDuplicateContentSetsPendingConfirmationWithExistingName() {
        _ = addExistingToken(name: "GitHub")
        fillValidTOTP()
        viewModel.name = "GitHub (rescanned)"

        viewModel.createToken()

        XCTAssertEqual(viewModel.pendingDuplicateAdd?.existingNames, ["GitHub"])
    }

    func testConfirmPendingDuplicateAddPersistsManualCreate() {
        _ = addExistingToken(name: "GitHub")
        fillValidTOTP()
        viewModel.name = "GitHub (rescanned)"
        viewModel.createToken()

        viewModel.confirmPendingDuplicateAdd()

        XCTAssertEqual(tokenStore.tokens.count, 2, "Both tokens must coexist after explicit confirmation")
        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertTrue(viewModel.shouldDismiss)
    }

    func testCancelPendingDuplicateAddDiscardsManualCreate() {
        _ = addExistingToken(name: "GitHub")
        fillValidTOTP()
        viewModel.name = "GitHub (rescanned)"
        viewModel.createToken()

        viewModel.cancelPendingDuplicateAdd()

        XCTAssertEqual(tokenStore.tokens.count, 1, "Cancelling must not add the duplicate")
        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertFalse(viewModel.shouldDismiss)
    }

    func testCreateTokenWithoutDuplicateDoesNotSetPendingConfirmation() {
        fillValidTOTP()
        viewModel.createToken()
        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(tokenStore.tokens.count, 1)
    }

    // MARK: - Duplicate confirmation (scanned QR)

    func testHandleScannedQRWithDuplicateContentDoesNotPersistImmediately() {
        let existing = addExistingToken(name: "GitHub")
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)"

        viewModel.handleScannedQR(uri)

        XCTAssertEqual(tokenStore.tokens.count, 1)
        XCTAssertEqual(tokenStore.tokens.first?.id, existing.id)
        XCTAssertNotNil(viewModel.pendingDuplicateAdd)
        XCTAssertFalse(viewModel.shouldDismiss)
    }

    func testConfirmPendingDuplicateAddPersistsScannedQR() {
        _ = addExistingToken(name: "GitHub")
        let uri = "otpauth://totp/Test:user@example.com?secret=\(validSecret)"
        viewModel.handleScannedQR(uri)

        viewModel.confirmPendingDuplicateAdd()

        XCTAssertEqual(tokenStore.tokens.count, 2)
        XCTAssertTrue(viewModel.shouldDismiss)
    }

    // MARK: - Duplicate confirmation (encrypted import)

    func testHandleEncryptedImportResultWithDuplicateContentDoesNotPersistImmediately() {
        let existing = addExistingToken(name: "GitHub")
        let imported = Token(name: "GitHub (imported)", issuer: nil, secret: validSecret.base32DecodedData!,
                             algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [imported], skipped: 0)

        viewModel.handleEncryptedImportResult(result)

        XCTAssertEqual(tokenStore.tokens.count, 1)
        XCTAssertEqual(tokenStore.tokens.first?.id, existing.id)
        XCTAssertNotNil(viewModel.pendingDuplicateAdd)
        XCTAssertFalse(viewModel.shouldDismiss)
    }

    func testConfirmPendingDuplicateAddPersistsEncryptedImport() {
        _ = addExistingToken(name: "GitHub")
        let imported = Token(name: "GitHub (imported)", issuer: nil, secret: validSecret.base32DecodedData!,
                             algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [imported], skipped: 0)
        viewModel.handleEncryptedImportResult(result)

        viewModel.confirmPendingDuplicateAdd()

        XCTAssertEqual(tokenStore.tokens.count, 2)
        XCTAssertTrue(viewModel.shouldDismiss)
    }

    // MARK: - Intra-batch duplicate collapse (no confirmation needed: nothing stored yet)

    func testImportBatchWithTwoIdenticalCandidatesCollapsesToOneWithoutConfirmation() {
        let secret = validSecret.base32DecodedData!
        let first = Token(name: "GitHub A", issuer: nil, secret: secret,
                          algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let second = Token(name: "GitHub B", issuer: nil, secret: secret,
                           algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [first, second], skipped: 0)

        viewModel.handleEncryptedImportResult(result)

        XCTAssertNil(viewModel.pendingDuplicateAdd, "Two never-stored candidates colliding with each other is not destructive")
        XCTAssertEqual(tokenStore.tokens.count, 1, "Only the first of the two identical candidates should be kept")
        XCTAssertEqual(tokenStore.tokens.first?.id, first.id)
        XCTAssertTrue(viewModel.shouldDismiss)
    }

    // MARK: - Cancel on a mixed batch keeps the non-duplicate tokens

    func testCancelPendingDuplicateAddOnMixedBatchKeepsNonDuplicateTokens() {
        let existing = addExistingToken(name: "GitHub")
        let duplicate = Token(name: "GitHub (imported)", issuer: nil, secret: validSecret.base32DecodedData!,
                              algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let unique = Token(name: "Discord", issuer: nil, secret: Data("distinct-secret-key".utf8),
                           algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [duplicate, unique], skipped: 0)
        viewModel.handleEncryptedImportResult(result)
        XCTAssertNotNil(viewModel.pendingDuplicateAdd, "Precondition: the batch must contain a real duplicate")

        viewModel.cancelPendingDuplicateAdd()

        XCTAssertNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(tokenStore.tokens.count, 2, "Existing token plus the non-duplicate import must survive")
        XCTAssertTrue(tokenStore.tokens.contains { $0.id == existing.id })
        XCTAssertTrue(tokenStore.tokens.contains { $0.id == unique.id })
        XCTAssertFalse(tokenStore.tokens.contains { $0.id == duplicate.id }, "The declined duplicate must not be added")
        XCTAssertTrue(viewModel.shouldDismiss, "A partially-successful import still dismisses, matching the old silent-skip behavior")
    }

    func testCancelPendingDuplicateAddOnAllDuplicateBatchAddsNothing() {
        let existing = addExistingToken(name: "GitHub")
        let duplicate = Token(name: "GitHub (imported)", issuer: nil, secret: validSecret.base32DecodedData!,
                              algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [duplicate], skipped: 0)
        viewModel.handleEncryptedImportResult(result)

        viewModel.cancelPendingDuplicateAdd()

        XCTAssertEqual(tokenStore.tokens.count, 1)
        XCTAssertEqual(tokenStore.tokens.first?.id, existing.id)
        XCTAssertFalse(viewModel.shouldDismiss, "Nothing was added, so the sheet should not report success")
    }

    // MARK: - Skipped-count alert does not race the duplicate-confirmation alert

    func testDuplicateAndSkippedCountAreNeverBothPendingAtOnce() {
        _ = addExistingToken(name: "GitHub")
        let duplicate = Token(name: "GitHub (imported)", issuer: nil, secret: validSecret.base32DecodedData!,
                              algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [duplicate], skipped: 3)

        viewModel.handleEncryptedImportResult(result)

        XCTAssertNotNil(viewModel.pendingDuplicateAdd)
        XCTAssertEqual(viewModel.importSkippedCount, 0,
                       "The skipped-count alert must not fire while a duplicate confirmation is pending")
    }

    func testSkippedCountSurfacesAfterDuplicateIsResolved() {
        _ = addExistingToken(name: "GitHub")
        let duplicate = Token(name: "GitHub (imported)", issuer: nil, secret: validSecret.base32DecodedData!,
                              algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let result = ExportImportManager.ImportResult(tokens: [duplicate], skipped: 3)
        viewModel.handleEncryptedImportResult(result)

        viewModel.confirmPendingDuplicateAdd()

        XCTAssertEqual(viewModel.importSkippedCount, 3)
    }
}
