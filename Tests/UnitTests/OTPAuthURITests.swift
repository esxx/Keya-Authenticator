import XCTest
@testable import Keya_Authenticator

final class OTPAuthURITests: XCTestCase {

    private let manager = ExportImportManager(tokenStore: TokenStore())

    private func parse(_ uri: String) throws -> Token {
        try manager.parseOTPAuthURI(uri)
    }

    // MARK: - Basic TOTP

    func testBasicTOTP() throws {
        let token = try parse("otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example")
        XCTAssertEqual(token.name, "alice@google.com")
        XCTAssertEqual(token.issuer, "Example")
        XCTAssertEqual(token.digits, 6)
        XCTAssertEqual(token.algorithm, .sha1)
        XCTAssertEqual(token.type, .totp)
        XCTAssertEqual(token.period, 30)
    }

    func testTOTPDefaultsApplied() throws {
        let token = try parse("otpauth://totp/Minimal?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(token.digits, 6)
        XCTAssertEqual(token.period, 30)
        XCTAssertEqual(token.algorithm, .sha1)
        XCTAssertNil(token.counter)
    }

    func testTOTPAllParameters() throws {
        let uri = "otpauth://totp/ACME%20Co:john.doe@email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60"
        let token = try parse(uri)
        XCTAssertEqual(token.name, "john.doe@email.com")
        XCTAssertEqual(token.issuer, "ACME Co")
        XCTAssertEqual(token.digits, 8)
        XCTAssertEqual(token.algorithm, .sha256)
        XCTAssertEqual(token.period, 60)
    }

    func testTOTPSHA512() throws {
        let token = try parse("otpauth://totp/Test:u@x.com?secret=JBSWY3DPEHPK3PXP&algorithm=SHA512")
        XCTAssertEqual(token.algorithm, .sha512)
    }

    // MARK: - HOTP

    func testBasicHOTP() throws {
        let token = try parse("otpauth://hotp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&counter=42")
        XCTAssertEqual(token.type, .hotp)
        XCTAssertEqual(token.counter, 42)
        XCTAssertNil(token.period)
    }

    func testHOTPDefaultCounter() throws {
        // Counter defaults to 0 when omitted
        let token = try parse("otpauth://hotp/Test?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(token.type, .hotp)
        XCTAssertEqual(token.counter, 0)
    }

    // MARK: - Label parsing

    func testNoIssuerInLabel() throws {
        let token = try parse("otpauth://totp/alice@google.com?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(token.name, "alice@google.com")
        XCTAssertNil(token.issuer)
    }

    func testIssuerFromLabelWhenQueryMissing() throws {
        let token = try parse("otpauth://totp/GitHub:username?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(token.issuer, "GitHub")
        XCTAssertEqual(token.name, "username")
    }

    func testQueryIssuerOverridesLabel() throws {
        let token = try parse("otpauth://totp/Label:name?secret=JBSWY3DPEHPK3PXP&issuer=QueryIssuer")
        XCTAssertEqual(token.issuer, "QueryIssuer")
    }

    func testLabelWithSpaces() throws {
        let token = try parse("otpauth://totp/ACME Co:john.doe@email.com?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(token.name, "john.doe@email.com")
        XCTAssertEqual(token.issuer, "ACME Co")
    }

    func testPercentEncodedEmailInLabel() throws {
        let token = try parse("otpauth://totp/Service:user%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Service")
        XCTAssertEqual(token.name, "user@example.com")
    }

    // MARK: - Real-world patterns

    func testRealWorldGitHub() throws {
        let token = try parse("otpauth://totp/GitHub:username?secret=JBSWY3DPEHPK3PXP&issuer=GitHub")
        XCTAssertFalse(token.secret.isEmpty)
        XCTAssertEqual(token.issuer, "GitHub")
    }

    func testRealWorldEmailAccount() throws {
        let token = try parse("otpauth://totp/Amazon:user%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Amazon")
        XCTAssertEqual(token.issuer, "Amazon")
        XCTAssertFalse(token.name.isEmpty)
    }

    // MARK: - Cross-type isolation

    func testCounterIgnoredForTOTP() throws {
        let token = try parse("otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&counter=123")
        XCTAssertNil(token.counter)
    }

    func testPeriodIgnoredForHOTP() throws {
        let token = try parse("otpauth://hotp/Test?secret=JBSWY3DPEHPK3PXP&period=60")
        XCTAssertNil(token.period)
    }

    // MARK: - Invalid input

    func testInvalidSecret() {
        XCTAssertThrowsError(try parse("otpauth://totp/Test:u@x.com?secret=INVALID!!!&issuer=Test"))
    }

    func testMissingSecret() {
        XCTAssertThrowsError(try parse("otpauth://totp/Test?issuer=Test"))
    }

    func testInvalidScheme() {
        XCTAssertThrowsError(try parse("http://totp/Test?secret=JBSWY3DPEHPK3PXP"))
    }

    func testInvalidType() {
        XCTAssertThrowsError(try parse("otpauth://steamotp/Test?secret=JBSWY3DPEHPK3PXP"))
    }

    // MARK: - Generator round-trips

    private func makeRoundTripToken(
        name: String,
        issuer: String?,
        period: Int? = 30,
        algorithm: Algorithm = .sha1,
        digits: Int = 6
    ) -> Token {
        Token(
            name: name,
            issuer: issuer,
            secret: "JBSWY3DPEHPK3PXP".base32DecodedData!,
            algorithm: algorithm,
            digits: digits,
            type: .totp,
            period: period
        )
    }

    @MainActor
    func testGeneratedURIRoundTripsBasic() throws {
        let token = makeRoundTripToken(name: "user@example.com", issuer: "Yahoo")
        let uri = QRCodeGenerator.generateOTPAuthURI(from: token)
        let parsed = try parse(uri)
        XCTAssertEqual(parsed.name, "user@example.com")
        XCTAssertEqual(parsed.issuer, "Yahoo")
        XCTAssertEqual(parsed.algorithm, .sha1)
        XCTAssertEqual(parsed.digits, 6)
        XCTAssertEqual(parsed.period, 30)
        XCTAssertEqual(parsed.secret, token.secret)
    }

    @MainActor
    func testGeneratedURIRoundTripsSpaces() throws {
        let token = makeRoundTripToken(name: "john.doe@email.com", issuer: "ACME Co")
        let uri = QRCodeGenerator.generateOTPAuthURI(from: token)
        XCTAssertFalse(uri.contains(" "), "URI must not contain raw spaces: \(uri)")
        let parsed = try parse(uri)
        XCTAssertEqual(parsed.issuer, "ACME Co")
        XCTAssertEqual(parsed.name, "john.doe@email.com")
    }

    @MainActor
    func testGeneratedURIDropsBase32Padding() {
        let token = makeRoundTripToken(name: "a", issuer: nil)
        let uri = QRCodeGenerator.generateOTPAuthURI(from: token)
        let secretValue = uri
            .components(separatedBy: "secret=").last?
            .components(separatedBy: "&").first ?? ""
        XCTAssertFalse(secretValue.contains("="),
                       "Padding '=' must not appear in secret value: \(secretValue)")
        XCTAssertFalse(secretValue.localizedCaseInsensitiveContains("%3D"),
                       "Percent-encoded '=' must not appear in secret value: \(secretValue)")
    }
}
