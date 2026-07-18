import XCTest
@testable import Keya_Authenticator

final class OTPGeneratorTests: XCTestCase {

    // MARK: - TOTP Tests

    func testTOTP_GoogleAuthenticatorExample() throws {
        let secret = "12345678901234567890".data(using: .ascii)!
        let time = Date(timeIntervalSince1970: 59)

        let code = try OTPGenerator.generateTOTP(
            secret: secret,
            time: time,
            period: 30,
            digits: 8,
            algorithm: .sha1
        )

        XCTAssertEqual(code, "94287082")
    }

    func testTOTP_SHA256() throws {
        let secret = "test-secret".data(using: .utf8)!
        let time = Date()

        let code = try OTPGenerator.generateTOTP(
            secret: secret,
            time: time,
            period: 30,
            digits: 6,
            algorithm: .sha256
        )

        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testTOTP_SHA512() throws {
        let secret = "another-secret".data(using: .utf8)!
        let time = Date()

        let code = try OTPGenerator.generateTOTP(
            secret: secret,
            time: time,
            period: 30,
            digits: 6,
            algorithm: .sha512
        )

        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testTOTP_8Digits() throws {
        let secret = "secret".data(using: .utf8)!
        let time = Date()

        let code = try OTPGenerator.generateTOTP(
            secret: secret,
            time: time,
            period: 30,
            digits: 8,
            algorithm: .sha1
        )

        XCTAssertEqual(code.count, 8)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testTOTP_InvalidDigitsThrows() {
        let secret = "secret".data(using: .utf8)!
        let time = Date()

        XCTAssertThrowsError(try OTPGenerator.generateTOTP(
            secret: secret,
            time: time,
            period: 30,
            digits: 7,
            algorithm: .sha1
        )) { error in
            XCTAssertTrue(error is TokenError)
        }
    }

    // MARK: - HOTP Tests

    func testHOTP_RFC4226Example() throws {
        let secret = "12345678901234567890".data(using: .ascii)!

        let testCases: [(counter: UInt64, expected: String)] = [
            (0, "755224"),
            (1, "287082"),
            (2, "359152"),
            (3, "969429"),
            (4, "338314"),
            (5, "254676"),
            (6, "287922"),
            (7, "162583"),
            (8, "399871"),
            (9, "520489")
        ]

        for (counter, expected) in testCases {
            let code = try OTPGenerator.generateHOTP(
                secret: secret,
                counter: counter,
                digits: 6,
                algorithm: .sha1
            )
            XCTAssertEqual(code, expected, "Failed for counter \(counter)")
        }
    }

    func testHOTP_8Digits() throws {
        let secret = "secret".data(using: .utf8)!

        let code = try OTPGenerator.generateHOTP(
            secret: secret,
            counter: 123,
            digits: 8,
            algorithm: .sha1
        )

        XCTAssertEqual(code.count, 8)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }
}
