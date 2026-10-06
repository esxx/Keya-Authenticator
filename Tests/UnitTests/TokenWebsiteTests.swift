import XCTest
@testable import Keya_Authenticator

final class TokenWebsiteTests: XCTestCase {

    private let validSecret = "JBSWY3DPEHPK3PXP".base32DecodedData!

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Storage compatibility

    func testTokenStoredWithoutWebsiteStillDecodes() throws {
        let token = Token(name: "alice", issuer: "GitHub", secret: validSecret)
        let data = try encoder().encode(token)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["website"], "Tokens without a website keep the previous storage format")

        let decoded = try decoder().decode(Token.self, from: data)
        XCTAssertNil(decoded.website)
        XCTAssertEqual(decoded.secret, validSecret)
        XCTAssertEqual(decoded.issuer, "GitHub")
    }

    func testWebsiteRoundTrips() throws {
        let token = Token(name: "alice", issuer: "GitHub", secret: validSecret, website: "github.com")
        let decoded = try decoder().decode(Token.self, from: encoder().encode(token))
        XCTAssertEqual(decoded.website, "github.com")
        XCTAssertEqual(decoded.id, token.id)
        XCTAssertEqual(decoded.secret, validSecret)
    }

    // MARK: - Normalization

    func testWebsiteDomainNormalizesInput() {
        XCTAssertEqual(Token.websiteDomain(from: "github.com"), "github.com")
        XCTAssertEqual(Token.websiteDomain(from: "  GitHub.com "), "github.com")
        XCTAssertEqual(Token.websiteDomain(from: "https://accounts.google.com/signin?x=1"), "accounts.google.com")
        XCTAssertEqual(Token.websiteDomain(from: "github.com/login"), "github.com")
        XCTAssertEqual(Token.websiteDomain(from: "xn--80ak6aa92e.com"), "xn--80ak6aa92e.com")
    }

    func testWebsiteDomainRejectsNonDomains() {
        XCTAssertNil(Token.websiteDomain(from: ""))
        XCTAssertNil(Token.websiteDomain(from: "GitHub"))
        XCTAssertNil(Token.websiteDomain(from: "my bank.com"))
        XCTAssertNil(Token.websiteDomain(from: "github.com."))
    }
}
