import XCTest
@testable import Keya_Authenticator

final class Base32Tests: XCTestCase {

    func testBase32Decoding_RFC4648Examples() {
        let testCases: [(encoded: String, expectedHex: String)] = [
            ("", ""),
            ("MY======", "66"),
            ("MZXQ====", "666f"),
            ("MZXW6===", "666f6f"),
            ("MZXW6YQ=", "666f6f62"),
            ("MZXW6YTB", "666f6f6261"),
            ("MZXW6YTBOI======", "666f6f626172"),
        ]

        for (encoded, expectedHex) in testCases {
            let decodedData = encoded.base32DecodedData
            let hexString = decodedData?.map { String(format: "%02x", $0) }.joined() ?? ""
            XCTAssertEqual(hexString, expectedHex, "Failed for encoded string: \(encoded)")
        }
    }

    func testBase32Decoding_GoogleAuthenticatorStyle() {
        let testCases = [
            "JBSWY3DPEHPK3PXP": "48656c6c6f21deadbeef",
            "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ": "3132333435363738393031323334353637383930",
        ]

        for (encoded, expectedHex) in testCases {
            let decodedData = encoded.base32DecodedData
            XCTAssertNotNil(decodedData, "Failed to decode: \(encoded)")

            let hexString = decodedData!.map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hexString, expectedHex, "Failed for encoded string: \(encoded)")
        }
    }

    func testBase32Encoding() {
        let testCases: [(data: Data, expected: String)] = [
            (Data([0x66]), "MY======"),
            (Data([0x66, 0x6F]), "MZXQ===="),
            (Data([0x66, 0x6F, 0x6F]), "MZXW6==="),
            (Data([0x66, 0x6F, 0x6F, 0x62]), "MZXW6YQ="),
            (Data([0x66, 0x6F, 0x6F, 0x62, 0x61]), "MZXW6YTB"),
        ]

        for (data, expected) in testCases {
            let encoded = data.base32EncodedString
            XCTAssertEqual(encoded, expected, "Failed for data: \(data.map { String(format: "%02x", $0) }.joined())")
        }
    }

    func testBase32RoundTrip() {
        let originalStrings = [
            "Hello World!",
            "Secret123",
            "Test with spaces and punctuation!",
            "1234567890",
            "🎯",
        ]

        for original in originalStrings {
            if let data = original.data(using: .utf8) {
                let encoded = data.base32EncodedString
                let decodedData = encoded.base32DecodedData
                let decodedString = decodedData.flatMap { String(data: $0, encoding: .utf8) }

                XCTAssertEqual(decodedString, original, "Round trip failed for: \(original)")
            }
        }
    }

    func testBase32InvalidCharacters() {
        let invalidStrings = [
            "1",
            "MZXW6===",
            "MZXW6====",
            "MZXW6Y===",
            "MZXW6YQ==",
            "MZXW6YT=",
            "MZXW6YTB=",
            "MZXW6YTB==",
            "MZXW6YTB===",
            "MZXW6YTB====",
        ]

        for invalid in invalidStrings {
            _ = invalid.base32DecodedData
        }
    }

    func testBase32RejectsPaddingInMiddle() {
        let malformed = [
            "JBSW=Y3DP",
            "=MZXW6YTB",
            "MZ=XW6YTB===",
            "MY==MY==",
        ]
        for input in malformed {
            XCTAssertNil(input.base32DecodedData,
                         "Non-trailing '=' must be rejected: \(input)")
        }
    }

    func testBase32AcceptsTrailingPaddingOnly() {
        XCTAssertNotNil("MZXW6YQ=".base32DecodedData)
        XCTAssertNotNil("MY======".base32DecodedData)
        XCTAssertNotNil("MZXW6YTB".base32DecodedData, "Unpadded input stays valid")
    }

    func testBase32Lowercase() {
        let lowercase = "mzxw6ytb"
        let uppercase = "MZXW6YTB"

        let lowercaseData = lowercase.base32DecodedData
        let uppercaseData = uppercase.base32DecodedData

        XCTAssertNotNil(lowercaseData)
        XCTAssertNotNil(uppercaseData)
        XCTAssertEqual(lowercaseData, uppercaseData)
    }
}
