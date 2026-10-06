import XCTest
@testable import Keya_Authenticator

@MainActor
final class TokenIntakeTests: XCTestCase {

    private let secret = "JBSWY3DPEHPK3PXP"

    // MARK: - Raw parameters (form prefill)

    func testParametersKeepRawValuesForTheForm() throws {
        let p = try XCTUnwrap(TokenIntake.parameters(fromOTPAuth: "otpauth://totp/?secret=\(secret)&digits=7&period=5"))
        XCTAssertEqual(p.name, "", "Prefill must not invent a name")
        XCTAssertEqual(p.digits, 7, "Unsupported values reach the form so its validation can explain them")
        XCTAssertEqual(p.period, 5)
    }

    func testEmptyIssuerInLabelBecomesNil() throws {
        let p = try XCTUnwrap(TokenIntake.parameters(fromOTPAuth: "otpauth://totp/:alice?secret=\(secret)"))
        XCTAssertNil(p.issuer)
        XCTAssertEqual(p.name, "alice")
    }

    func testIssuerParameterWinsOverLabel() throws {
        let p = try XCTUnwrap(TokenIntake.parameters(fromOTPAuth: "otpauth://totp/Label:alice?secret=\(secret)&issuer=Param"))
        XCTAssertEqual(p.issuer, "Param")
    }

    // MARK: - Validated token (direct add)

    func testTokenFallsBackToImportedTokenName() throws {
        let token = try TokenIntake.token(fromOTPAuth: "otpauth://totp/?secret=\(secret)")
        XCTAssertEqual(token.name, "Imported Token")
    }

    func testTokenWithoutAccountNameIsNamedAfterIssuer() throws {
        let fromLabel = try TokenIntake.token(fromOTPAuth: "otpauth://totp/GitHub:?secret=\(secret)")
        XCTAssertEqual(fromLabel.name, "GitHub")
        XCTAssertEqual(fromLabel.issuer, "GitHub")
        let fromParameter = try TokenIntake.token(fromOTPAuth: "otpauth://totp/?secret=\(secret)&issuer=GitHub")
        XCTAssertEqual(fromParameter.name, "GitHub")
        let prefill = try XCTUnwrap(TokenIntake.parameters(fromOTPAuth: "otpauth://totp/GitHub:?secret=\(secret)"))
        XCTAssertEqual(prefill.name, "", "The form still gets the raw label")
    }

    func testTokenRejectionReasons() {
        XCTAssertThrowsError(try TokenIntake.token(fromOTPAuth: "otpauth://totp/a?secret=AB")) {
            XCTAssertEqual($0 as? TokenIntakeError, .invalidSecret)
        }
        XCTAssertThrowsError(try TokenIntake.token(fromOTPAuth: "otpauth://totp/a?secret=\(secret)&digits=7")) {
            XCTAssertEqual($0 as? TokenIntakeError, .unsupportedDigits)
        }
        XCTAssertThrowsError(try TokenIntake.token(fromOTPAuth: "otpauth://totp/a?secret=\(secret)&period=5")) {
            XCTAssertEqual($0 as? TokenIntakeError, .unsupportedPeriod)
        }
        XCTAssertThrowsError(try TokenIntake.token(fromOTPAuth: "https://example.com")) {
            XCTAssertEqual($0 as? TokenIntakeError, .notOTPAuth)
        }
    }

    // MARK: - Scheme case (RFC 3986 §3.1)

    func testUppercaseSchemeIsAccepted() throws {
        let token = try TokenIntake.token(fromOTPAuth: "OTPAUTH://TOTP/GITHUB:ALICE?SECRET=\(secret)&ISSUER=GITHUB")
        XCTAssertEqual(token.issuer, "GITHUB")
        XCTAssertEqual(token.type, .totp)
        XCTAssertTrue(TokenIntake.hasScheme("OTPAUTH-MIGRATION://offline?data=x", TokenIntake.migrationScheme))
        XCTAssertFalse(TokenIntake.hasScheme("otpauthx://totp", TokenIntake.otpAuthScheme))
    }

    func testFileLinesAcceptUppercaseScheme() throws {
        let text = "OTPAUTH://totp/GitHub:user?secret=\(secret)&issuer=GitHub"
        let result = try OTPAuthURIParser().parse(from: Data(text.utf8))
        XCTAssertEqual(result.tokens.map(\.issuer), ["GitHub"])
    }

    // MARK: - Migration

    func testUndecodableMigrationReturnsNil() {
        XCTAssertNil(TokenIntake.tokens(fromMigration: "otpauth-migration://offline?data=%%%"))
    }
}
