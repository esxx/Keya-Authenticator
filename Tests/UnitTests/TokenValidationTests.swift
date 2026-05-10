import XCTest
@testable import Keya_Authenticator

final class TokenValidationTests: XCTestCase {

    private let validSecret = "JBSWY3DPEHPK3PXP".base32DecodedData!


    private func totpToken(digits: Int = 6, period: Int = 30) -> Token {
        Token(name: "Test", issuer: "Test",
              secret: validSecret, algorithm: .sha1,
              digits: digits, type: .totp, period: period, counter: nil)
    }

    private func hotpToken(counter: UInt64 = 0) -> Token {
        Token(name: "Test", issuer: "Test",
              secret: validSecret, algorithm: .sha1,
              digits: 6, type: .hotp, period: nil, counter: counter)
    }

    // MARK: - Token generation smoke tests

    func testTOTPGeneratesValidCode() throws {
        let code = try totpToken().generateCode()
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testHOTPGeneratesValidCode() throws {
        let code = try hotpToken().generateCode()
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testTOTPWith8Digits() throws {
        let code = try totpToken(digits: 8).generateCode()
        XCTAssertEqual(code.count, 8)
    }

    func testTOTPCodesAreDeterministic() throws {
        let token = totpToken()
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let code1 = try token.generateCode(time: fixedDate)
        let code2 = try token.generateCode(time: fixedDate)
        XCTAssertEqual(code1, code2)
    }

    func testTOTPCodeChangesAtPeriodBoundary() throws {
        let token = totpToken()
        let code1 = try token.generateCode(time: Date(timeIntervalSince1970: 0))
        let code2 = try token.generateCode(time: Date(timeIntervalSince1970: 30))
        XCTAssertNotEqual(code1, code2)
    }

    func testHOTPCounterAffectsCode() throws {
        let code0 = try hotpToken(counter: 0).generateCode()
        let code1 = try hotpToken(counter: 1).generateCode()
        XCTAssertNotEqual(code0, code1)
    }

    func testTOTPCodeStableWithinPeriod() throws {
        let token = totpToken()
        // Two timestamps 1 second apart inside the same 30 s window must produce the same code.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let code1 = try token.generateCode(time: base)
        let code2 = try token.generateCode(time: base.addingTimeInterval(1))
        XCTAssertEqual(code1, code2)
    }

    // MARK: - RFC 4226 HOTP test vectors (Appendix D)

    func testHOTPRFC4226Vectors() throws {
        let secret = "12345678901234567890".data(using: .ascii)!
        let expected = ["755224", "287082", "359152", "969429", "338314",
                        "254676", "287922", "162583", "399871", "520489"]
        for (counter, exp) in expected.enumerated() {
            let token = Token(name: "T", issuer: nil, secret: secret,
                              digits: 6, type: .hotp, period: nil, counter: UInt64(counter))
            let code = try token.generateCode()
            XCTAssertEqual(code, exp, "Counter \(counter)")
        }
    }

    // MARK: - RFC 6238 TOTP test vectors (Appendix B, SHA-1)

    func testTOTPRFC6238SHA1() throws {
        let secret = "12345678901234567890".data(using: .ascii)!
        let cases: [(time: Double, expected: String)] = [
            (59,          "94287082"),
            (1111111109,  "07081804"),
            (1111111111,  "14050471"),
            (1234567890,  "89005924"),
            (2000000000,  "69279037"),
            (20000000000, "65353130"),
        ]
        for (time, exp) in cases {
            let token = Token(name: "T", issuer: nil, secret: secret,
                              algorithm: .sha1, digits: 8, type: .totp,
                              period: 30, counter: nil)
            let code = try token.generateCode(time: Date(timeIntervalSince1970: time))
            XCTAssertEqual(code, exp, "Time \(time)")
        }
    }

}
