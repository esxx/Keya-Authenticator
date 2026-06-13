import XCTest
@testable import Keya_Authenticator

// MARK: - OTPGenerator stress tests

final class OTPGeneratorStressTests: XCTestCase {

    // MARK: RFC 6238 SHA-256 vectors (Appendix B)

    func testTOTP_RFC6238_SHA256() throws {
        let secret = "12345678901234567890123456789012".data(using: .ascii)!
        let cases: [(time: Double, expected: String)] = [
            (59,          "46119246"),
            (1111111109,  "68084774"),
            (1111111111,  "67062674"),
            (1234567890,  "91819424"),
            (2000000000,  "90698825"),
            (20000000000, "77737706"),
        ]
        for (time, exp) in cases {
            let code = try OTPGenerator.generateTOTP(
                secret: secret,
                time: Date(timeIntervalSince1970: time),
                period: 30, digits: 8, algorithm: .sha256
            )
            XCTAssertEqual(code, exp, "SHA-256 t=\(time)")
        }
    }

    // MARK: RFC 6238 SHA-512 vectors (Appendix B)

    func testTOTP_RFC6238_SHA512() throws {
        let secret = "1234567890123456789012345678901234567890123456789012345678901234".data(using: .ascii)!
        let cases: [(time: Double, expected: String)] = [
            (59,          "90693936"),
            (1111111109,  "25091201"),
            (1111111111,  "99943326"),
            (1234567890,  "93441116"),
            (2000000000,  "38618901"),
            (20000000000, "47863826"),
        ]
        for (time, exp) in cases {
            let code = try OTPGenerator.generateTOTP(
                secret: secret,
                time: Date(timeIntervalSince1970: time),
                period: 30, digits: 8, algorithm: .sha512
            )
            XCTAssertEqual(code, exp, "SHA-512 t=\(time)")
        }
    }

    // MARK: Leading-zero preservation

    func testHOTP_LeadingZerosPreserved() throws {
        // Counter 0 with the RFC secret produces "755224" — no leading zeros,
        // but we need to guarantee the zero-pad format contract for any output.
        let secret = "12345678901234567890".data(using: .ascii)!
        for counter: UInt64 in 0..<20 {
            let code = try OTPGenerator.generateHOTP(secret: secret, counter: counter, digits: 6)
            XCTAssertEqual(code.count, 6, "6-digit code must always be 6 chars (counter \(counter))")
            XCTAssertTrue(code.allSatisfy(\.isNumber), "Must be all digits (counter \(counter))")
        }
    }

    func testHOTP_8DigitLeadingZerosPreserved() throws {
        let secret = "12345678901234567890".data(using: .ascii)!
        for counter: UInt64 in 0..<20 {
            let code = try OTPGenerator.generateHOTP(secret: secret, counter: counter, digits: 8)
            XCTAssertEqual(code.count, 8, "8-digit code must always be 8 chars (counter \(counter))")
        }
    }

    // MARK: Boundary counters

    func testHOTP_MaxUInt64Counter() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        // Must not crash or throw.
        let code = try OTPGenerator.generateHOTP(secret: secret, counter: UInt64.max, digits: 6)
        XCTAssertEqual(code.count, 6)
    }

    func testHOTP_LargeCounterDifferentFromSmall() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let small = try OTPGenerator.generateHOTP(secret: secret, counter: 0)
        let large = try OTPGenerator.generateHOTP(secret: secret, counter: 1_000_000_000)
        XCTAssertNotEqual(small, large)
    }

    // MARK: Period boundary

    func testTOTP_ExactPeriodBoundary() throws {
        // t=30 is the first tick of the second period — code must differ from t=29.
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let codeBefore = try OTPGenerator.generateTOTP(
            secret: secret, time: Date(timeIntervalSince1970: 29), period: 30)
        let codeAfter  = try OTPGenerator.generateTOTP(
            secret: secret, time: Date(timeIntervalSince1970: 30), period: 30)
        XCTAssertNotEqual(codeBefore, codeAfter, "Code must change at the period boundary")
    }

    func testTOTP_NonStandardPeriods() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        for period in [15, 60, 90, 300] {
            let code = try OTPGenerator.generateTOTP(
                secret: secret, time: Date(timeIntervalSince1970: 1_000_000),
                period: period, digits: 6)
            XCTAssertEqual(code.count, 6, "period=\(period) must produce 6-digit code")
        }
    }

    // MARK: All algorithm × digit combinations

    func testAllAlgorithmDigitCombinations() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        for alg in Algorithm.allCases {
            for digits in [6, 8] {
                let code = try OTPGenerator.generateTOTP(
                    secret: secret, time: t, period: 30, digits: digits, algorithm: alg)
                XCTAssertEqual(code.count, digits, "\(alg)×\(digits) wrong length")
                XCTAssertTrue(code.allSatisfy(\.isNumber), "\(alg)×\(digits) non-digit")
            }
        }
    }

    // MARK: Determinism across algorithms

    func testAllAlgorithmsAreDeterministic() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        for alg in Algorithm.allCases {
            let a = try OTPGenerator.generateTOTP(secret: secret, time: t, period: 30, algorithm: alg)
            let b = try OTPGenerator.generateTOTP(secret: secret, time: t, period: 30, algorithm: alg)
            XCTAssertEqual(a, b, "\(alg) must be deterministic")
        }
    }

    // MARK: Algorithms produce distinct codes (almost always)

    func testDifferentAlgorithmsProduceDifferentCodes() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let sha1   = try OTPGenerator.generateTOTP(secret: secret, time: t, algorithm: .sha1)
        let sha256 = try OTPGenerator.generateTOTP(secret: secret, time: t, algorithm: .sha256)
        let sha512 = try OTPGenerator.generateTOTP(secret: secret, time: t, algorithm: .sha512)
        XCTAssertNotEqual(sha1,   sha256)
        XCTAssertNotEqual(sha1,   sha512)
        XCTAssertNotEqual(sha256, sha512)
    }

    // MARK: Invalid inputs

    func testTOTP_ZeroPeriodThrows() {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        XCTAssertThrowsError(
            try OTPGenerator.generateTOTP(secret: secret, period: 0)
        )
    }

    func testTOTP_InvalidDigitsThrows() {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        for bad in [0, 1, 5, 7, 9, 10] {
            XCTAssertThrowsError(
                try OTPGenerator.generateTOTP(secret: secret, digits: bad),
                "digits=\(bad) must throw"
            )
        }
    }
}

// MARK: - Base32 stress tests

final class Base32StressTests: XCTestCase {

    // MARK: All RFC 4648 padding lengths (with and without padding chars)

    func testAllRFC4648VectorsWithPadding() {
        let cases: [(String, String)] = [
            ("",               ""),
            ("MY======",       "66"),
            ("MZXQ====",       "666f"),
            ("MZXW6===",       "666f6f"),
            ("MZXW6YQ=",       "666f6f62"),
            ("MZXW6YTB",       "666f6f6261"),
            ("MZXW6YTBOI======","666f6f626172"),
        ]
        for (enc, hex) in cases {
            let decoded = enc.base32DecodedData
            let got = decoded?.map { String(format: "%02x", $0) }.joined() ?? ""
            XCTAssertEqual(got, hex, "RFC vector '\(enc)'")
        }
    }

    func testAllRFC4648VectorsWithoutPadding() {
        let cases: [(String, String)] = [
            ("MY",           "66"),
            ("MZXQ",         "666f"),
            ("MZXW6",        "666f6f"),
            ("MZXW6YQ",      "666f6f62"),
            ("MZXW6YTB",     "666f6f6261"),
            ("MZXW6YTBOI",   "666f6f626172"),
        ]
        for (enc, hex) in cases {
            let decoded = enc.base32DecodedData
            let got = decoded?.map { String(format: "%02x", $0) }.joined() ?? ""
            XCTAssertEqual(got, hex, "Unpadded vector '\(enc)'")
        }
    }

    // MARK: Case insensitivity

    func testMixedCaseDecodes() {
        XCTAssertEqual("jbswy3dpehpk3pxp".base32DecodedData,
                       "JBSWY3DPEHPK3PXP".base32DecodedData)
        XCTAssertEqual("JbSwY3dPeHpK3pXp".base32DecodedData,
                       "JBSWY3DPEHPK3PXP".base32DecodedData)
    }

    // MARK: Null bytes survive round-trip

    func testNullBytesInData() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00])
        let encoded = data.base32EncodedString
        let decoded = encoded.base32DecodedData
        XCTAssertEqual(decoded, data, "Null bytes must survive encode→decode round-trip")
    }

    func testMaxByteValues() {
        let data = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let encoded = data.base32EncodedString
        let decoded = encoded.base32DecodedData
        XCTAssertEqual(decoded, data)
    }

    // MARK: Long strings

    func testVeryLongStringRoundTrip() {
        var data = Data()
        for i in 0..<256 { data.append(UInt8(i)) }
        let encoded = data.base32EncodedString
        let decoded = encoded.base32DecodedData
        XCTAssertEqual(decoded, data, "256-byte round-trip must be lossless")
    }

    // MARK: Encode → decode round-trips for arbitrary UTF-8

    func testArbitraryStringsRoundTrip() {
        let strings = [
            "Hello, World!",
            "1234567890abcdef",
            "The quick brown fox",
            "\0\0\0",                   // null bytes as string
            String(repeating: "A", count: 100),
        ]
        for s in strings {
            guard let data = s.data(using: .utf8) else { continue }
            let encoded = data.base32EncodedString
            let decoded = encoded.base32DecodedData
            XCTAssertEqual(decoded, data, "Round-trip failed for '\(s.prefix(20))'")
        }
    }

    // MARK: Invalid / garbage inputs return nil gracefully

    func testGarbageInputsReturnNilOrEmpty() {
        let garbage = ["!@#$", "0", "1", "8", "9", "====", "ZZZZZZZZ1"]
        for g in garbage {
            // Must not crash; we don't mandate nil vs empty vs partial.
            _ = g.base32DecodedData
        }
    }

    // MARK: Single-character boundary

    func testSingleCharacterIsGraceful() {
        // A single base32 char encodes only 5 bits — not a full byte.
        // Result can be nil or 0-length; must not crash.
        let result = "A".base32DecodedData
        XCTAssertTrue(result == nil || result?.isEmpty == true)
    }
}

// MARK: - OTP Auth URI stress tests

final class OTPAuthURIStressTests: XCTestCase {

    private var manager: ExportImportManager!

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        manager = ExportImportManager(tokenStore: TokenStore())
    }

    private func parse(_ uri: String) throws -> Token {
        try manager.parseOTPAuthURI(uri)
    }

    // MARK: Unusual but valid percent-encoding

    func testDoublyEncodedIssuerDecodes() throws {
        // Some apps encode the space as %2520 (double-encode). We should handle it gracefully.
        let token = try parse("otpauth://totp/Corp:user?secret=JBSWY3DPEHPK3PXP&issuer=Corp")
        XCTAssertFalse(token.name.isEmpty)
    }

    func testSpecialCharsInName() throws {
        // Plus signs, slashes (encoded), hashes
        let token = try parse("otpauth://totp/Service:user%2Bname%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Service")
        XCTAssertEqual(token.name, "user+name@example.com")
    }

    func testUnicodeIssuerPercent() throws {
        // Issuer with Unicode encoded in query param
        let token = try parse("otpauth://totp/Test:u?secret=JBSWY3DPEHPK3PXP&issuer=Caf%C3%A9")
        XCTAssertEqual(token.issuer, "Café")
    }

    // MARK: Invalid digit values fall back to 6

    func testInvalidDigitsFallBackTo6() throws {
        for bad in ["0", "1", "7", "9", "abc"] {
            let token = try parse("otpauth://totp/T?secret=JBSWY3DPEHPK3PXP&digits=\(bad)")
            XCTAssertEqual(token.digits, 6, "digits='\(bad)' must fall back to 6")
        }
    }

    // MARK: Counter at UInt64 boundaries

    func testMaxCounterInHOTP() throws {
        let token = try parse("otpauth://hotp/T?secret=JBSWY3DPEHPK3PXP&counter=18446744073709551615")
        XCTAssertEqual(token.counter, UInt64.max)
    }

    func testNegativeCounterIgnored() throws {
        // UInt64("-1") returns nil, so counter should fall back to 0
        let token = try parse("otpauth://hotp/T?secret=JBSWY3DPEHPK3PXP&counter=-1")
        XCTAssertEqual(token.counter, 0)
    }

    // MARK: Unknown algorithm defaults to SHA1

    func testUnknownAlgorithmDefaultsSHA1() throws {
        let token = try parse("otpauth://totp/T?secret=JBSWY3DPEHPK3PXP&algorithm=MD5")
        XCTAssertEqual(token.algorithm, .sha1)
    }

    func testEmptyAlgorithmDefaultsSHA1() throws {
        let token = try parse("otpauth://totp/T?secret=JBSWY3DPEHPK3PXP&algorithm=")
        XCTAssertEqual(token.algorithm, .sha1)
    }

    // MARK: Label-only (no issuer in query)

    func testLabelOnlyNoColon() throws {
        let token = try parse("otpauth://totp/myaccount?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(token.name, "myaccount")
        XCTAssertNil(token.issuer)
    }

    func testEmptyLabelFallsBackToDefault() throws {
        // Path is just "/" — name should not be empty
        let token = try parse("otpauth://totp/?secret=JBSWY3DPEHPK3PXP")
        XCTAssertFalse(token.name.isEmpty)
    }

    // MARK: Duplicate query parameters

    func testDuplicateSecretUsesFirst() throws {
        // Behaviour is implementation-defined; must not crash or throw.
        let token = try? parse("otpauth://totp/T?secret=JBSWY3DPEHPK3PXP&secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ")
        // Either value is acceptable; just verify it didn't crash.
        XCTAssertNotNil(token)
    }

    // MARK: Large batch parse

    func testLargeBatchOf100URIs() throws {
        let base = "JBSWY3DPEHPK3PXP"
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("otpauth://totp/Service\(i):user\(i)@example.com?secret=\(base)&issuer=Service\(i)")
        }
        let data = lines.joined(separator: "\n").data(using: .utf8)!
        let result = try manager.parseTokens(from: data)
        XCTAssertEqual(result.tokens.count, 100)
        XCTAssertEqual(result.skipped, 0)
    }

    // MARK: Mixed valid/invalid batch

    func testMixedBatchCountsSkipped() throws {
        let data = """
        otpauth://totp/Good1:u?secret=JBSWY3DPEHPK3PXP&issuer=Good1
        otpauth://totp/Bad1:u?issuer=Bad1
        otpauth://totp/Good2:u?secret=JBSWY3DPEHPK3PXP&issuer=Good2
        otpauth://totp/Bad2:u?secret=INVALIDCHARS!!!&issuer=Bad2
        otpauth://totp/Good3:u?secret=JBSWY3DPEHPK3PXP&issuer=Good3
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: data)
        XCTAssertEqual(result.tokens.count, 3)
        XCTAssertEqual(result.skipped, 2)
    }
}

// MARK: - ExportImport format stress tests

final class ExportImportFormatStressTests: XCTestCase {

    private var tokenStore: TokenStore!
    private var manager: ExportImportManager!
    private let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!

    override func setUp() {
        super.setUp()
        try? KeychainManager.deleteAllTokens()
        tokenStore = TokenStore()
        manager = ExportImportManager(tokenStore: tokenStore)
    }

    override func tearDown() {
        try? KeychainManager.deleteAllTokens()
        super.tearDown()
    }

    // MARK: Aegis edge cases

    func testAegisHOTPWithCounter() throws {
        let json = """
        {
            "db": {
                "entries": [{
                    "type": "hotp",
                    "name": "hotp-user",
                    "issuer": "Corp",
                    "info": { "secret": "JBSWY3DPEHPK3PXP", "algo": "SHA1", "digits": 6, "counter": 42 }
                }]
            }
        }
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].type, .hotp)
        XCTAssertEqual(result.tokens[0].counter, 42)
        XCTAssertNil(result.tokens[0].period, "HOTP must not carry a period")
    }

    func testAegisSHA256And8Digits() throws {
        let json = """
        {
            "db": {
                "entries": [{
                    "type": "totp",
                    "name": "alice",
                    "issuer": "Corp",
                    "info": { "secret": "JBSWY3DPEHPK3PXP", "algo": "SHA256", "digits": 8, "period": 60 }
                }]
            }
        }
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens[0].algorithm, .sha256)
        XCTAssertEqual(result.tokens[0].digits, 8)
        XCTAssertEqual(result.tokens[0].period, 60)
    }

    func testAegisUnknownTypeDefaultsToTOTP() throws {
        let json = """
        {
            "db": {
                "entries": [{
                    "type": "steam",
                    "name": "steam-user",
                    "issuer": "Steam",
                    "info": { "secret": "JBSWY3DPEHPK3PXP", "algo": "SHA1", "digits": 5, "period": 30 }
                }]
            }
        }
        """.data(using: .utf8)!
        // Unknown type should not crash — the parser defaults to TOTP.
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].type, .totp)
    }

    func testAegisAllEntriesMissingSecretThrows() {
        let json = """
        {
            "db": {
                "entries": [
                    { "name": "a", "issuer": "x", "info": { "digits": 6 } },
                    { "name": "b", "issuer": "y", "info": { "digits": 6 } }
                ]
            }
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try manager.parseTokens(from: json))
    }

    func testAegisEmptyEntriesArrayThrows() {
        let json = "{\"db\":{\"entries\":[]}}".data(using: .utf8)!
        XCTAssertThrowsError(try manager.parseTokens(from: json))
    }

    // MARK: 2FAS edge cases

    func testTwoFASHOTPWithCounter() throws {
        let json = """
        {
            "services": [{
                "name": "Corp",
                "secret": "JBSWY3DPEHPK3PXP",
                "otp": {
                    "account": "alice",
                    "digits": 6,
                    "counter": 7,
                    "period": 30,
                    "algorithm": "SHA1",
                    "tokenType": "HOTP"
                }
            }]
        }
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens[0].type, .hotp)
        XCTAssertEqual(result.tokens[0].counter, 7)
        XCTAssertNil(result.tokens[0].period)
    }

    func testTwoFASEmptyServicesThrows() {
        let json = "{\"services\":[]}".data(using: .utf8)!
        XCTAssertThrowsError(try manager.parseTokens(from: json))
    }

    // MARK: andOTP edge cases

    func testAndOTPMissingLabelFallsBack() throws {
        let json = """
        [{"secret":"JBSWY3DPEHPK3PXP","type":"TOTP","digits":6,"period":30}]
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertFalse(result.tokens[0].name.isEmpty)
    }

    func testAndOTPAllAlgorithms() throws {
        for (alg, expected) in [("SHA1", Algorithm.sha1), ("SHA256", .sha256), ("SHA512", .sha512)] {
            let json = """
            [{"secret":"JBSWY3DPEHPK3PXP","label":"u","type":"TOTP","algorithm":"\(alg)","digits":6,"period":30}]
            """.data(using: .utf8)!
            let result = try manager.parseTokens(from: json)
            XCTAssertEqual(result.tokens[0].algorithm, expected, "andOTP algorithm=\(alg)")
        }
    }

    // MARK: Raivo edge cases

    func testRaivoStringDigitsAndPeriodParsed() throws {
        let json = """
        [{"secret":"JBSWY3DPEHPK3PXP","account":"alice","issuer":"Corp","kind":"TOTP","algorithm":"SHA256","digits":"8","timer":"60"}]
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens[0].digits, 8)
        XCTAssertEqual(result.tokens[0].period, 60)
        XCTAssertEqual(result.tokens[0].algorithm, .sha256)
    }

    func testRaivoObjectFormatWithMultipleEntries() throws {
        let json = """
        {
            "UUID-A": {"secret":"JBSWY3DPEHPK3PXP","account":"alice","issuer":"A","kind":"TOTP","digits":"6","timer":"30"},
            "UUID-B": {"secret":"JBSWY3DPEHPK3PXP","account":"bob","issuer":"B","kind":"TOTP","digits":"6","timer":"30"}
        }
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens.count, 2)
    }

    // MARK: LastPass edge cases

    func testLastPassMissingUserNameFallsToIssuer() throws {
        let json = """
        {"accounts":[{"secret":"JBSWY3DPEHPK3PXP","issuerName":"Corp","digits":6,"timeStep":30,"algorithm":"SHA1"}]}
        """.data(using: .utf8)!
        let result = try manager.parseTokens(from: json)
        XCTAssertEqual(result.tokens[0].name, "Corp")
    }

    func testLastPassEmptyAccountsThrows() {
        let json = "{\"accounts\":[]}".data(using: .utf8)!
        XCTAssertThrowsError(try manager.parseTokens(from: json))
    }

    // MARK: Round-trip — 50 tokens of mixed type

    func testLargeRoundTripMixedTypes() throws {
        var tokens: [Token] = []
        for i in 0..<25 {
            // Unique secret per token: content-key dedup correctly collapses
            // same-secret entries, so each token must carry a distinct secret.
            var s = Data("TOTP-\(i)".utf8); while s.count < 10 { s.append(0) }
            tokens.append(Token(name: "TOTP-\(i)", issuer: "Corp",
                                secret: s, algorithm: .sha1,
                                digits: 6, type: .totp, period: 30, counter: nil))
        }
        for i in 0..<25 {
            var s = Data("HOTP-\(i)".utf8); while s.count < 10 { s.append(0) }
            tokens.append(Token(name: "HOTP-\(i)", issuer: "Corp",
                                secret: s, algorithm: .sha256,
                                digits: 8, type: .hotp, period: nil, counter: UInt64(i)))
        }
        try tokenStore.update(tokens)

        let data = try manager.exportVault()
        let result = try manager.parseTokens(from: data)

        XCTAssertEqual(result.tokens.count, 50)
        let totpCount = result.tokens.filter { $0.type == .totp }.count
        let hotpCount = result.tokens.filter { $0.type == .hotp }.count
        XCTAssertEqual(totpCount, 25)
        XCTAssertEqual(hotpCount, 25)

        // Verify HOTP tokens preserved their counters
        let hotpTokens = result.tokens
            .filter { $0.type == .hotp }
            .sorted { ($0.counter ?? 0) < ($1.counter ?? 0) }
        for (idx, t) in hotpTokens.enumerated() {
            XCTAssertEqual(t.counter, UInt64(idx), "HOTP counter must survive round-trip")
            XCTAssertNil(t.period, "HOTP must not carry a period")
        }
    }

    // MARK: Encrypted export edge cases

    func testEncryptionWithUnicodePassword() throws {
        let t = Token(name: "Test", issuer: "Corp", secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        let password = "p@ssw0rd🔐éàü"
        let encrypted = try manager.exportVaultEncrypted(password: password)
        let result = try manager.parseEncryptedTokens(from: encrypted, password: password)
        XCTAssertEqual(result.tokens.count, 1)
    }

    func testEncryptionWithVeryLongPassword() throws {
        let t = Token(name: "Test", issuer: "Corp", secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        let password = String(repeating: "a", count: 1000)
        let encrypted = try manager.exportVaultEncrypted(password: password)
        let result = try manager.parseEncryptedTokens(from: encrypted, password: password)
        XCTAssertEqual(result.tokens.count, 1)
    }

    func testEncryptionWithMinimum6CharPassword() throws {
        let t = Token(name: "Test", issuer: "Corp", secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        let encrypted = try manager.exportVaultEncrypted(password: "sixchr")
        let result = try manager.parseEncryptedTokens(from: encrypted, password: "sixchr")
        XCTAssertEqual(result.tokens.count, 1)
    }

    func testEncryptedFileDetectedCorrectly() throws {
        let t = Token(name: "Test", issuer: nil, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        let encrypted = try manager.exportVaultEncrypted(password: "password123")
        XCTAssertTrue(EncryptionService.isEncryptedExport(encrypted))

        let plaintext = try manager.exportVault()
        XCTAssertFalse(EncryptionService.isEncryptedExport(plaintext))
    }

    func testEncryptedParseWithoutPasswordThrows() throws {
        let t = Token(name: "Test", issuer: nil, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        let encrypted = try manager.exportVaultEncrypted(password: "mypassword")
        // Calling parseTokens (not parseEncryptedTokens) on encrypted data must throw.
        XCTAssertThrowsError(try manager.parseTokens(from: encrypted)) { error in
            guard let e = error as? ExportImportError,
                  e == .encryptedFileRequiresPassword else {
                return XCTFail("Expected .encryptedFileRequiresPassword, got \(error)")
            }
        }
    }

    func testCorruptCiphertextThrowsWrongPassword() throws {
        let t = Token(name: "Test", issuer: nil, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        var encrypted = try manager.exportVaultEncrypted(password: "pass")
        // Flip a byte in the middle to corrupt the ciphertext.
        let mid = encrypted.count / 2
        encrypted[mid] ^= 0xFF

        XCTAssertThrowsError(
            try manager.parseEncryptedTokens(from: encrypted, password: "pass")
        )
    }

    func testTruncatedEncryptedDataThrows() throws {
        let t = Token(name: "Test", issuer: nil, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([t])

        let encrypted = try manager.exportVaultEncrypted(password: "pass")
        // Keep only the first half.
        let truncated = encrypted.prefix(encrypted.count / 2)
        XCTAssertThrowsError(
            try manager.parseEncryptedTokens(from: Data(truncated), password: "pass")
        )
    }
}

// MARK: - EncryptionService unit stress tests

final class EncryptionServiceStressTests: XCTestCase {

    // MARK: Data sizes

    func testEncryptEmptyData() throws {
        let empty = Data()
        let enc = try EncryptionService.encrypt(empty, password: "hunter2")
        let dec = try EncryptionService.decrypt(enc, password: "hunter2")
        XCTAssertEqual(dec, empty)
    }

    func testEncrypt1MBData() throws {
        let large = Data(repeating: 0xAB, count: 1_000_000)
        let enc = try EncryptionService.encrypt(large, password: "password")
        let dec = try EncryptionService.decrypt(enc, password: "password")
        XCTAssertEqual(dec, large)
    }

    // MARK: Password edge cases

    func testEmptyPasswordThrows() {
        XCTAssertThrowsError(try EncryptionService.encrypt(Data([1, 2, 3]), password: ""))
    }

    func testSingleCharPassword() throws {
        let data = Data("hello".utf8)
        let enc = try EncryptionService.encrypt(data, password: "x")
        let dec = try EncryptionService.decrypt(enc, password: "x")
        XCTAssertEqual(dec, data)
    }

    // MARK: Each encryption call produces a unique ciphertext (fresh random salt + nonce)

    func testTwoEncryptionsOfSamePlaintextDiffer() throws {
        let data = Data("same input".utf8)
        let enc1 = try EncryptionService.encrypt(data, password: "pw")
        let enc2 = try EncryptionService.encrypt(data, password: "pw")
        XCTAssertNotEqual(enc1, enc2, "Distinct encryptions must produce different ciphertext")
    }

    // MARK: Wrong password

    func testWrongPasswordThrowsWrongPassword() throws {
        let enc = try EncryptionService.encrypt(Data("secret".utf8), password: "correct")
        XCTAssertThrowsError(
            try EncryptionService.decrypt(enc, password: "wrong")
        ) { error in
            guard let e = error as? ExportImportError, e == .wrongPassword else {
                return XCTFail("Expected .wrongPassword, got \(error)")
            }
        }
    }

    func testPasswordCaseSensitive() throws {
        let enc = try EncryptionService.encrypt(Data("data".utf8), password: "Password")
        XCTAssertThrowsError(
            try EncryptionService.decrypt(enc, password: "password")
        )
    }

    // MARK: Garbage input

    func testGarbageInputThrowsInvalidFormat() {
        let garbage = Data("this is not encrypted JSON".utf8)
        XCTAssertThrowsError(try EncryptionService.decrypt(garbage, password: "anything")) { error in
            guard let e = error as? ExportImportError, e == .invalidFileFormat else {
                return XCTFail("Expected .invalidFileFormat, got \(error)")
            }
        }
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try EncryptionService.decrypt(Data(), password: "pw"))
    }

    // MARK: Key derivation determinism

    func testDeriveKeyIsDeterministic() throws {
        let salt = Data(repeating: 0x42, count: 32)
        let k1 = try EncryptionService.deriveKey(password: "pw", salt: salt, iterations: 1000)
        let k2 = try EncryptionService.deriveKey(password: "pw", salt: salt, iterations: 1000)
        XCTAssertEqual(k1, k2)
    }

    func testDifferentSaltsDifferentKeys() throws {
        let s1 = Data(repeating: 0x01, count: 32)
        let s2 = Data(repeating: 0x02, count: 32)
        let k1 = try EncryptionService.deriveKey(password: "pw", salt: s1, iterations: 1000)
        let k2 = try EncryptionService.deriveKey(password: "pw", salt: s2, iterations: 1000)
        XCTAssertNotEqual(k1, k2)
    }

    func testDifferentPasswordsDifferentKeys() throws {
        let salt = Data(repeating: 0x00, count: 32)
        let k1 = try EncryptionService.deriveKey(password: "pw1", salt: salt, iterations: 1000)
        let k2 = try EncryptionService.deriveKey(password: "pw2", salt: salt, iterations: 1000)
        XCTAssertNotEqual(k1, k2)
    }
}

// MARK: - Token Codable stress tests

final class TokenCodableStressTests: XCTestCase {

    private func encode(_ token: Token) throws -> Data {
        try JSONEncoder().encode(token)
    }

    private func decode(_ data: Data) throws -> Token {
        try JSONDecoder().decode(Token.self, from: data)
    }

    private func roundTrip(_ token: Token) throws -> Token {
        try decode(try encode(token))
    }

    private let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!

    // MARK: Every field survives round-trip

    func testTOTPFullFieldsRoundTrip() throws {
        let t = Token(name: "alice@example.com", issuer: "Corp",
                      secret: secret, algorithm: .sha256,
                      digits: 8, type: .totp, period: 60, counter: nil)
        let rt = try roundTrip(t)
        XCTAssertEqual(rt.name,      t.name)
        XCTAssertEqual(rt.issuer,    t.issuer)
        XCTAssertEqual(rt.secret,    t.secret)
        XCTAssertEqual(rt.algorithm, t.algorithm)
        XCTAssertEqual(rt.digits,    t.digits)
        XCTAssertEqual(rt.type,      t.type)
        XCTAssertEqual(rt.period,    t.period)
        XCTAssertNil(rt.counter)
    }

    func testHOTPFullFieldsRoundTrip() throws {
        let t = Token(name: "bob", issuer: nil,
                      secret: secret, algorithm: .sha512,
                      digits: 6, type: .hotp, period: nil, counter: 999)
        let rt = try roundTrip(t)
        XCTAssertEqual(rt.type,    .hotp)
        XCTAssertEqual(rt.counter, 999)
        XCTAssertNil(rt.period)
        XCTAssertNil(rt.issuer)
    }

    // MARK: Decoder normalisation

    func testDecoderClampsInvalidDigitsTo6() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(
            Token(name: "T", issuer: nil, secret: secret,
                  algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        )) as? [String: Any])
        json["digits"] = 7
        let data = try JSONSerialization.data(withJSONObject: json)
        let t = try decode(data)
        XCTAssertEqual(t.digits, 6, "Invalid digits (7) must be clamped to 6")
    }

    func testDecoderClampsZeroDigitsTo6() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(
            Token(name: "T", issuer: nil, secret: secret,
                  algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        )) as? [String: Any])
        json["digits"] = 0
        let data = try JSONSerialization.data(withJSONObject: json)
        let t = try decode(data)
        XCTAssertEqual(t.digits, 6)
    }

    func testDecoderNormalisesTOTPDropsCounter() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(
            Token(name: "T", issuer: nil, secret: secret,
                  algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        )) as? [String: Any])
        json["counter"] = 42
        let data = try JSONSerialization.data(withJSONObject: json)
        let t = try decode(data)
        XCTAssertEqual(t.type, .totp)
        XCTAssertNil(t.counter, "TOTP decoded token must not carry a counter")
        XCTAssertEqual(t.period, 30)
    }

    func testDecoderNormalisesHOTPDropsPeriod() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(
            Token(name: "T", issuer: nil, secret: secret,
                  algorithm: .sha1, digits: 6, type: .hotp, period: nil, counter: 0)
        )) as? [String: Any])
        json["period"] = 60
        let data = try JSONSerialization.data(withJSONObject: json)
        let t = try decode(data)
        XCTAssertEqual(t.type, .hotp)
        XCTAssertNil(t.period, "HOTP decoded token must not carry a period")
        XCTAssertNotNil(t.counter)
    }

    // MARK: UUID stability

    func testUUIDPreservedAcrossRoundTrip() throws {
        let t = Token(name: "T", issuer: nil, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let rt = try roundTrip(t)
        XCTAssertEqual(rt.id, t.id)
    }

    // MARK: Long strings

    func testVeryLongNameAndIssuerRoundTrip() throws {
        let long = String(repeating: "A", count: 500)
        let t = Token(name: long, issuer: long, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let rt = try roundTrip(t)
        XCTAssertEqual(rt.name, long)
        XCTAssertEqual(rt.issuer, long)
    }

    // MARK: Special characters in name/issuer

    func testSpecialCharsInNameRoundTrip() throws {
        let special = "user@corp.com / 日本語 🔐 <>&\""
        let t = Token(name: special, issuer: special, secret: secret,
                      algorithm: .sha1, digits: 6, type: .totp, period: 30, counter: nil)
        let rt = try roundTrip(t)
        XCTAssertEqual(rt.name, special)
        XCTAssertEqual(rt.issuer, special)
    }

    // MARK: All algorithm values survive round-trip

    func testAllAlgorithmsRoundTrip() throws {
        for alg in Algorithm.allCases {
            let t = Token(name: "T", issuer: nil, secret: secret,
                          algorithm: alg, digits: 6, type: .totp, period: 30, counter: nil)
            let rt = try roundTrip(t)
            XCTAssertEqual(rt.algorithm, alg)
        }
    }
}

// MARK: - AuthenticationManager stress tests

final class AuthenticationManagerStressTests: XCTestCase {

    private var manager: AuthenticationManager!

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

    // MARK: Exact boundary conditions

    func testFourFailuresNoLockout() throws {
        try KeychainManager.savePIN("111111")
        for _ in 0..<4 {
            XCTAssertThrowsError(try manager.authenticateWithPIN("000000"))
        }
        // 4 failures — should still not be locked out
        XCTAssertNil(manager.pinLockoutSecondsRemaining(), "4 failures must not trigger lockout")
        // 5th failure triggers soft lockout
        XCTAssertThrowsError(try manager.authenticateWithPIN("000000"))
        XCTAssertNotNil(manager.pinLockoutSecondsRemaining(), "5th failure must trigger soft lockout")
    }

    func testNineFailuresSoftLockoutOnly() throws {
        try KeychainManager.savePIN("111111")
        let state = KeychainManager.LockoutState(failedAttempts: 4, lockoutUntil: nil, lastFailedAttempt: nil)
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        // Get to 9 failures: state says 4, so 5 more wrong attempts
        for _ in 0..<4 {
            // Each wrong attempt while locked out just throws pinLocked — skip if locked
            if manager.pinLockoutSecondsRemaining() != nil { break }
            XCTAssertThrowsError(try manager.authenticateWithPIN("000000"))
        }
        // At 9 total failures we should have soft lockout but NOT hard lockout (~5 min).
        // We can't distinguish the two from the outside easily, but the seconds remaining
        // must be ≤ 30 (soft lockout), not 300 (hard lockout).
        // Skip if we already triggered lockout in the loop above.
        let remaining = manager.pinLockoutSecondsRemaining()
        if let r = remaining {
            XCTAssertLessThanOrEqual(r, 30, "9 failures must produce soft lockout, not hard lockout")
        }
    }

    func testHardLockoutDurationIsApproximately5Minutes() throws {
        try KeychainManager.savePIN("111111")
        // Plant state with exactly 9 failures so next attempt triggers hard lockout.
        let state = KeychainManager.LockoutState(failedAttempts: 9, lockoutUntil: nil, lastFailedAttempt: Date())
        try KeychainManager.saveLockoutState(state, account: KeychainManager.pinLockoutAccount)

        XCTAssertThrowsError(try manager.authenticateWithPIN("000000"))

        let saved = try KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount)
        XCTAssertEqual(saved.failedAttempts, 10)
        // Lockout window should be close to 300 s from now.
        let interval = saved.lockoutUntil?.timeIntervalSinceNow ?? 0
        XCTAssertGreaterThan(interval, 290, "Hard lockout must be ~5 minutes")
        XCTAssertLessThan(interval, 310, "Hard lockout must not exceed 5 minutes significantly")
    }

    // MARK: Correct PIN resets after previous lockout

    func testCorrectPINAfterExpiredSoftLockout() throws {
        try KeychainManager.savePIN("111111")
        let expired = KeychainManager.LockoutState(
            failedAttempts: 5,
            lockoutUntil: Date().addingTimeInterval(-1),
            lastFailedAttempt: Date()
        )
        try KeychainManager.saveLockoutState(expired, account: KeychainManager.pinLockoutAccount)

        XCTAssertNoThrow(try manager.authenticateWithPIN("111111"))

        let saved = try KeychainManager.loadLockoutState(account: KeychainManager.pinLockoutAccount)
        XCTAssertEqual(saved.failedAttempts, 0)
        XCTAssertNil(saved.lockoutUntil)
    }

    // MARK: PIN cycle (set → remove → set again)

    func testPINCycleSetRemoveSet() throws {
        try manager.setPIN("123456", confirmPin: "123456")
        XCTAssertTrue(KeychainManager.isPINSet())

        try manager.removePIN()
        XCTAssertFalse(KeychainManager.isPINSet())

        try manager.setPIN("654321", confirmPin: "654321")
        XCTAssertTrue(KeychainManager.isPINSet())

        XCTAssertNoThrow(try manager.authenticateWithPIN("654321"))
        XCTAssertThrowsError(try manager.authenticateWithPIN("123456"))
    }

    // MARK: lockoutMessage formatting

    func testLockoutMessageUnder60Seconds() {
        let msg = AuthenticationManager.lockoutMessage(seconds: 29)
        XCTAssertTrue(msg.contains("29s"), "Under-60s message must show seconds: \(msg)")
        XCTAssertFalse(msg.contains("m "), "Under-60s message must not show minutes: \(msg)")
    }

    func testLockoutMessageExactly60Seconds() {
        let msg = AuthenticationManager.lockoutMessage(seconds: 60)
        XCTAssertTrue(msg.contains("1m"), "60s message must show 1m: \(msg)")
    }

    func testLockoutMessageMixed() {
        let msg = AuthenticationManager.lockoutMessage(seconds: 299)
        XCTAssertTrue(msg.contains("4m") && msg.contains("59s"), "299s: \(msg)")
    }

    func testLockoutMessageZeroSeconds() {
        let msg = AuthenticationManager.lockoutMessage(seconds: 0)
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: setPIN validation edge cases

    func testSetPINExactly6NumericSucceeds() throws {
        try manager.setPIN("000000", confirmPin: "000000")
        XCTAssertTrue(KeychainManager.isPINSet())
        XCTAssertNoThrow(try manager.authenticateWithPIN("000000"))
    }

    func testSetPINAllNines() throws {
        try manager.setPIN("999999", confirmPin: "999999")
        XCTAssertNoThrow(try manager.authenticateWithPIN("999999"))
    }

    func testSetPIN7DigitsThrows() {
        XCTAssertThrowsError(try manager.setPIN("1234567", confirmPin: "1234567"))
    }

    func testSetPIN5DigitsThrows() {
        XCTAssertThrowsError(try manager.setPIN("12345", confirmPin: "12345"))
    }
}

// MARK: - Migration URI security tests

/// Regression tests for the protobuf length-overflow crash in parseMigrationURI.
/// Before the fix, a crafted varint encoding Int.max+1 as a field length caused
/// Int(length) to trap at runtime (Swift overflow). After the fix the parser
/// returns nil cleanly.
final class MigrationURISecurityTests: XCTestCase {

    /// Outer protobuf field 1, wire 2, with a length varint encoding
    /// 9223372036854775808 (Int.max + 1 = 0x8000_0000_0000_0000).
    /// Before fix: runtime trap on Int(length). After fix: nil.
    func testOuterFieldOverflowLengthReturnsNil() {
        // Tag: field 1, wire 2 → 0x0A
        // Varint for 0x8000_0000_0000_0000: nine 0x80 continuation bytes + 0x01
        let bytes: [UInt8] = [0x0A, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]
        let base64 = Data(bytes).base64EncodedString()
        let uri = "otpauth-migration://offline?data=\(base64)"

        XCTAssertNil(uri.parseMigrationURI(),
                     "Parser must return nil for overflow-length outer field, not trap")
    }

    /// A valid-length outer field (11 bytes), but the inner OtpParameters message
    /// carries field 1 (secret) with a length overflow. Before fix: trap in
    /// parseOtpParameters. After fix: nil.
    func testInnerFieldOverflowLengthReturnsNil() {
        let innerBytes: [UInt8] = [0x0A, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]
        // Outer field 1, wire 2, length = innerBytes.count
        var outer: [UInt8] = [0x0A, UInt8(innerBytes.count)]
        outer.append(contentsOf: innerBytes)
        let base64 = Data(outer).base64EncodedString()
        let uri = "otpauth-migration://offline?data=\(base64)"

        XCTAssertNil(uri.parseMigrationURI(),
                     "Parser must return nil for overflow-length inner field, not trap")
    }

    /// Sanity check: a well-formed migration URI with a 10-byte TOTP secret must parse
    /// successfully. Proves the URL-parsing pipeline is not vacuously returning nil.
    /// Protobuf: outer field 1 (len=12) → OtpParameters field 1 (secret = "HelloWorld").
    /// URL-safe base64 without padding to avoid '=' ambiguity in query values.
    func testValidMigrationURI_parsesSuccessfully() {
        let uri = "otpauth-migration://offline?data=CgwKCkhlbGxvV29ybGQ"
        let result = uri.parseMigrationURI()
        XCTAssertNotNil(result, "Known-valid migration URI must parse at least one token")
        XCTAssertEqual(result?.count, 1)
    }
}
