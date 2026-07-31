import XCTest
@testable import Keya_Authenticator

final class DeepStressTests: XCTestCase {

    // MARK: - Deterministic PRNG

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private let algorithms: [Algorithm] = [.sha1, .sha256, .sha512]

    private func randomSecret(_ rng: inout SeededGenerator, minBytes: Int = 10, maxBytes: Int = 64) -> Data {
        let count = Int.random(in: minBytes ... maxBytes, using: &rng)
        return Data((0 ..< count).map { _ in UInt8.random(in: 0 ... 255, using: &rng) })
    }

    private func randomBase32(_ rng: inout SeededGenerator, length: Int) -> String {
        String((0 ..< length).map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &rng)] })
    }

    // MARK: - Base32 fuzz

    func testBase32NeverCrashesOnArbitraryInput() {
        var rng = SeededGenerator(seed: 0xBA5E32)
        let pool = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567abcdefghijklmnopqrstuvwxyz0189=+/ \t\n\u{00E9}\u{4E2D}\u{1F600}")
        for _ in 0 ..< 5000 {
            let len = Int.random(in: 0 ... 80, using: &rng)
            let s = String((0 ..< len).map { _ in pool[Int.random(in: 0 ..< pool.count, using: &rng)] })
            _ = s.base32DecodedData
        }
    }

    func testBase32RoundTripsArbitraryBinaryData() {
        var rng = SeededGenerator(seed: 0xD00D)
        for _ in 0 ..< 2000 {
            let original = randomSecret(&rng, minBytes: 0, maxBytes: 128)
            let encoded = original.base32EncodedString
            XCTAssertEqual(encoded.base32DecodedData, original,
                           "Round trip must preserve bytes for \(original.count)-byte input")
        }
    }

    func testBase32DecodedLengthFollowsSpec() {
        var rng = SeededGenerator(seed: 0x5EC)
        for _ in 0 ..< 1000 {
            let len = Int.random(in: 1 ... 120, using: &rng)
            let input = randomBase32(&rng, length: len)
            guard let decoded = input.base32DecodedData else {
                return XCTFail("Valid base32 alphabet input must decode: \(input)")
            }
            XCTAssertEqual(decoded.count, len * 5 / 8,
                           "Decoded length must be floor(n*5/8) for \(len) chars")
        }
    }

    func testBase32RejectsNonTrailingPaddingUnderFuzz() {
        var rng = SeededGenerator(seed: 0x9AD)
        for _ in 0 ..< 2000 {
            let len = Int.random(in: 2 ... 40, using: &rng)
            var chars = Array(randomBase32(&rng, length: len))
            let insertAt = Int.random(in: 0 ..< chars.count, using: &rng)
            chars.insert("=", at: insertAt)
            let malformed = String(chars)
            XCTAssertNil(malformed.base32DecodedData,
                         "Padding before payload must be rejected: \(malformed)")
        }
    }

    func testBase32TrailingPaddingIsEquivalentToUnpadded() {
        var rng = SeededGenerator(seed: 0x7AD7)
        for _ in 0 ..< 1000 {
            let len = Int.random(in: 1 ... 40, using: &rng)
            let base = randomBase32(&rng, length: len)
            let padCount = Int.random(in: 1 ... 8, using: &rng)
            let padded = base + String(repeating: "=", count: padCount)
            XCTAssertEqual(padded.base32DecodedData, base.base32DecodedData,
                           "Trailing padding must not change the decoded value")
        }
    }

    // MARK: - OTP invariants under fuzz

    func testOTPAlwaysProducesExactNumericDigits() throws {
        var rng = SeededGenerator(seed: 0x0A7)
        for _ in 0 ..< 1500 {
            let secret = randomSecret(&rng)
            let digits = Bool.random(using: &rng) ? 6 : 8
            let algorithm = algorithms[Int.random(in: 0 ..< 3, using: &rng)]
            let counter = UInt64.random(in: 0 ... UInt64.max, using: &rng)

            let hotp = try OTPGenerator.generateHOTP(
                secret: secret, counter: counter, digits: digits, algorithm: algorithm
            )
            XCTAssertEqual(hotp.count, digits, "HOTP must be exactly \(digits) chars, got \(hotp)")
            XCTAssertTrue(hotp.allSatisfy(\.isNumber), "HOTP must be numeric, got \(hotp)")
        }
    }

    func testOTPIsDeterministicUnderFuzz() throws {
        var rng = SeededGenerator(seed: 0xDE7)
        for _ in 0 ..< 800 {
            let secret = randomSecret(&rng)
            let digits = Bool.random(using: &rng) ? 6 : 8
            let algorithm = algorithms[Int.random(in: 0 ..< 3, using: &rng)]
            let counter = UInt64.random(in: 0 ... 1_000_000, using: &rng)

            let a = try OTPGenerator.generateHOTP(secret: secret, counter: counter, digits: digits, algorithm: algorithm)
            let b = try OTPGenerator.generateHOTP(secret: secret, counter: counter, digits: digits, algorithm: algorithm)
            XCTAssertEqual(a, b, "Same inputs must produce the same code")
        }
    }

    func testTOTPIsStableWithinItsPeriod() throws {
        var rng = SeededGenerator(seed: 0x57AB)
        for _ in 0 ..< 400 {
            let secret = randomSecret(&rng)
            let period = Int.random(in: 15 ... 300, using: &rng)
            let base = Double(Int.random(in: 0 ... 2_000_000_000, using: &rng))
            let windowStart = (base / Double(period)).rounded(.down) * Double(period)

            let first = try OTPGenerator.generateTOTP(
                secret: secret, time: Date(timeIntervalSince1970: windowStart), period: period
            )
            let last = try OTPGenerator.generateTOTP(
                secret: secret, time: Date(timeIntervalSince1970: windowStart + Double(period) - 1), period: period
            )
            XCTAssertEqual(first, last, "Code must not change inside a \(period)s window")
        }
    }

    func testHOTPProducesWellDistributedCodes() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        var seen = Set<String>()
        for counter in 0 ..< 1000 {
            seen.insert(try OTPGenerator.generateHOTP(secret: secret, counter: UInt64(counter)))
        }
        XCTAssertGreaterThan(seen.count, 950,
                             "1000 counters should yield near-unique codes, got \(seen.count)")
    }

    func testEmptySecretIsRejectedRatherThanProducingAWrongCode() {
        XCTAssertThrowsError(try OTPGenerator.generateHOTP(secret: Data(), counter: 0)) { error in
            XCTAssertEqual(error as? TokenError, .invalidSecret("Token secret is empty"))
        }
        XCTAssertThrowsError(try OTPGenerator.generateTOTP(secret: Data()))

        let corrupted = Token(name: "Corrupt", secret: Data(), algorithm: .sha1,
                              digits: 6, type: .totp, period: 30)
        XCTAssertThrowsError(try corrupted.generateCode(),
                             "A zero-length secret must never yield a plausible code")
    }

    func testShortButNonEmptySecretsStillGenerate() throws {
        for byteCount in 1 ... 9 {
            let secret = Data(repeating: 0xAB, count: byteCount)
            let code = try OTPGenerator.generateHOTP(secret: secret, counter: 1)
            XCTAssertEqual(code.count, 6,
                           "Legacy short secrets must keep working (\(byteCount) bytes)")
        }
    }

    // MARK: - contentKey dedup contract

    func testContentKeyIgnoresPresentationFields() {
        var rng = SeededGenerator(seed: 0xC0DE)
        for _ in 0 ..< 500 {
            let secret = randomSecret(&rng)
            let digits = Bool.random(using: &rng) ? 6 : 8
            let algorithm = algorithms[Int.random(in: 0 ..< 3, using: &rng)]
            let period = Int.random(in: 15 ... 300, using: &rng)

            let a = Token(name: "Alpha", issuer: "One", secret: secret, algorithm: algorithm,
                          digits: digits, type: .totp, period: period, isFavorite: false)
            let b = Token(name: "Beta", issuer: "Two", secret: secret, algorithm: algorithm,
                          digits: digits, type: .totp, period: period, isFavorite: true,
                          groupName: "Work", createdAt: Date(timeIntervalSince1970: 0))

            XCTAssertEqual(a.contentKey, b.contentKey,
                           "Name, issuer, favourite and group must not affect dedup identity")
        }
    }

    func testContentKeyDistinguishesCryptographicFields() {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let other = "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ".base32DecodedData!
        let base = Token(name: "T", secret: secret, algorithm: .sha1, digits: 6, type: .totp, period: 30)

        let variants: [(String, Token)] = [
            ("secret", Token(name: "T", secret: other, algorithm: .sha1, digits: 6, type: .totp, period: 30)),
            ("algorithm", Token(name: "T", secret: secret, algorithm: .sha256, digits: 6, type: .totp, period: 30)),
            ("digits", Token(name: "T", secret: secret, algorithm: .sha1, digits: 8, type: .totp, period: 30)),
            ("period", Token(name: "T", secret: secret, algorithm: .sha1, digits: 6, type: .totp, period: 60)),
        ]
        for (field, variant) in variants {
            XCTAssertNotEqual(base.contentKey, variant.contentKey,
                              "Changing \(field) must change dedup identity")
        }
    }

    // MARK: - Format confusion and dispatch determinism

    func testAmbiguousRaivoAndOTPPayloadPrefersRaivo() throws {
        let json = """
        [{"secret":"JBSWY3DPEHPK3PXP","kind":"TOTP","account":"raivo-name",
          "label":"andotp-name","issuer":"Both","digits":"6","timer":"30"}]
        """
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)
        let result = try manager.parseTokens(from: Data(json.utf8))

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, "raivo-name",
                       "Raivo precedes andOTP in the adapter chain")
        XCTAssertNoThrow(try RaivoParser().parse(from: Data(json.utf8)))
        XCTAssertNoThrow(try AndOTPParser().parse(from: Data(json.utf8)))
    }

    func testAmbiguousAegisAndTwoFASPayloadPrefersAegis() throws {
        let json = """
        {"db":{"entries":[{"name":"aegis-name","issuer":"A",
           "info":{"secret":"JBSWY3DPEHPK3PXP","digits":6,"period":30}}]},
         "services":[{"name":"twofas-name","secret":"HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ"}]}
        """
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)
        let result = try manager.parseTokens(from: Data(json.utf8))

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, "aegis-name",
                       "Aegis precedes 2FAS in the adapter chain")
    }

    func testParseTokensIsDeterministicAcrossRepeatedCalls() throws {
        let json = """
        [{"secret":"JBSWY3DPEHPK3PXP","kind":"TOTP","account":"a","label":"b","digits":"6","timer":"30"},
         {"secret":"HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ","kind":"HOTP","account":"c","counter":"5"}]
        """
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)
        let data = Data(json.utf8)

        let reference = try manager.parseTokens(from: data).tokens.map(\.name)
        for _ in 0 ..< 50 {
            XCTAssertEqual(try manager.parseTokens(from: data).tokens.map(\.name), reference,
                           "Dispatch must not depend on dictionary iteration order")
        }
    }

    func testBrokenLeadingFormatDoesNotDiscardValidLaterFormat() throws {
        let json = """
        {"db":{"entries":[{"name":"broken","info":{"digits":6}}]},
         "services":[{"name":"rescue","secret":"JBSWY3DPEHPK3PXP"}]}
        """
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)
        let result = try manager.parseTokens(from: Data(json.utf8))

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "rescue",
                       "A broken Aegis envelope must not abort the chain before 2FAS is tried")
    }

    func testUnparseableFileStillReportsSpecificError() {
        let json = #"{"db":{"entries":[{"name":"broken","info":{"digits":6}}]}}"#
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)

        XCTAssertThrowsError(try manager.parseTokens(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? ExportImportError, .invalidFileFormat,
                           "A recognised but broken format must keep its specific error")
        }
    }

    func testUpdatePreservesInsertionOrderAcrossRepeatedRuns() throws {
        let names = (0 ..< 12).map { "Token\($0)" }
        for _ in 0 ..< 20 {
            let store = TokenStore()
            let tokens = names.map { name -> Token in
                var secret = Data(name.utf8)
                while secret.count < 10 { secret.append(0) }
                return Token(name: name, secret: secret, algorithm: .sha1,
                             digits: 6, type: .totp, period: 30)
            }
            UserDefaults.standard.removeObject(forKey: "tokenSortOrder")
            try store.update(tokens)
            XCTAssertEqual(store.tokens.map(\.name), names,
                           "update() must preserve the order it was given")
            try? KeychainManager.deleteAllTokens()
        }
    }

    // MARK: - Adversarial payloads

    func testParsersSurviveDeeplyNestedJSON() {
        let depth = 2000
        let nested = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let data = Data(nested.utf8)
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)

        XCTAssertThrowsError(try manager.parseTokens(from: data))
        XCTAssertThrowsError(try AegisParser().parse(from: data))
        XCTAssertThrowsError(try RaivoParser().parse(from: data))
        XCTAssertThrowsError(try AndOTPParser().parse(from: data))
    }

    func testParsersSurviveTypeConfusion() {
        let payloads = [
            #"{"db":{"entries":[{"name":123,"info":{"secret":null,"digits":"six"}}]}}"#,
            #"{"db":{"entries":"not-an-array"}}"#,
            #"{"services":[{"name":[],"secret":{}}]}"#,
            #"{"accounts":[{"secret":42,"digits":[6]}]}"#,
            #"[{"secret":null,"kind":true,"digits":{},"timer":[]}]"#,
            #"[{"secret":"JBSWY3DPEHPK3PXP","digits":"not-a-number","period":null}]"#,
            #"{"db":null}"#,
            #"{"uris":[null,42,{}]}"#,
            "null",
            "[]",
            "{}",
        ]
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)

        for payload in payloads {
            let data = Data(payload.utf8)
            _ = try? manager.parseTokens(from: data)
            _ = try? AegisParser().parse(from: data)
            _ = try? TwoFASParser().parse(from: data)
            _ = try? LastPassParser().parse(from: data)
            _ = try? RaivoParser().parse(from: data)
            _ = try? AndOTPParser().parse(from: data)
            _ = try? KeyaPlaintextParser().parse(from: data)
        }
    }

    func testParsersSurviveTruncatedAndBinaryGarbage() {
        var rng = SeededGenerator(seed: 0xF022)
        let store = TokenStore()
        let manager = ExportImportManager(tokenStore: store)

        for _ in 0 ..< 500 {
            let length = Int.random(in: 0 ... 256, using: &rng)
            let data = Data((0 ..< length).map { _ in UInt8.random(in: 0 ... 255, using: &rng) })
            _ = try? manager.parseTokens(from: data)
            _ = try? AegisParser().parse(from: data)
            _ = try? RaivoParser().parse(from: data)
        }
    }

    func testOversizedSecretsAreRejectedOrHandled() throws {
        let hugeSecret = String(repeating: "A", count: 100_000)
        let json = """
        {"db":{"entries":[{"name":"huge","info":{"secret":"\(hugeSecret)","digits":6,"period":30}}]}}
        """
        let result = try AegisParser().parse(from: Data(json.utf8))
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertNoThrow(try result.tokens[0].generateCode())
    }

    // MARK: - Scale

    func testAegisImportOfTenThousandEntries() throws {
        var entries: [String] = []
        entries.reserveCapacity(10_000)
        for i in 0 ..< 10_000 {
            entries.append("""
            {"name":"user\(i)","issuer":"Corp\(i % 50)",
             "info":{"secret":"JBSWY3DPEHPK3PXP","digits":6,"period":30}}
            """)
        }
        let json = "{\"db\":{\"entries\":[\(entries.joined(separator: ","))]}}"

        let start = Date()
        let result = try AegisParser().parse(from: Data(json.utf8))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.tokens.count, 10_000)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertLessThan(elapsed, 20, "10k-entry import took \(elapsed)s")
    }

    @MainActor
    func testTokenCodableRoundTripUnderFuzz() throws {
        var rng = SeededGenerator(seed: 0xC0DEC)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for _ in 0 ..< 500 {
            let isTOTP = Bool.random(using: &rng)
            let nameLength = Int.random(in: 1 ... 40, using: &rng)
            let name = randomBase32(&rng, length: nameLength)
            let hasIssuer = Bool.random(using: &rng)
            let issuerValue = randomBase32(&rng, length: 8)
            let secret = randomSecret(&rng)
            let algorithm = algorithms[Int.random(in: 0 ..< 3, using: &rng)]
            let digits = Bool.random(using: &rng) ? 6 : 8
            let periodValue = Int.random(in: 15 ... 300, using: &rng)
            let counterValue = UInt64.random(in: 0 ... UInt64.max, using: &rng)
            let favourite = Bool.random(using: &rng)

            let original = Token(
                name: name,
                issuer: hasIssuer ? issuerValue : nil,
                secret: secret,
                algorithm: algorithm,
                digits: digits,
                type: isTOTP ? .totp : .hotp,
                period: isTOTP ? periodValue : nil,
                counter: isTOTP ? nil : counterValue,
                isFavorite: favourite
            )
            let decoded = try decoder.decode(Token.self, from: try encoder.encode(original))

            XCTAssertEqual(decoded.secret, original.secret)
            XCTAssertEqual(decoded.algorithm, original.algorithm)
            XCTAssertEqual(decoded.digits, original.digits)
            XCTAssertEqual(decoded.type, original.type)
            XCTAssertEqual(decoded.period, original.period)
            XCTAssertEqual(decoded.counter, original.counter)
            XCTAssertEqual(decoded.id, original.id)
            XCTAssertEqual(decoded.contentKey, original.contentKey)
        }
    }

    // MARK: - BrandKeyword fuzz

    func testBrandKeywordNeverReturnsEmptyForNonEmptyHost() {
        var rng = SeededGenerator(seed: 0xB4A2D)
        let pool = Array("abcdefghijklmnopqrstuvwxyz0123456789.-")
        for _ in 0 ..< 3000 {
            let len = Int.random(in: 1 ... 40, using: &rng)
            let host = String((0 ..< len).map { _ in pool[Int.random(in: 0 ..< pool.count, using: &rng)] })
            let keyword = BrandKeyword.extract(fromHost: host)
            XCTAssertFalse(keyword.contains(" "), "Keyword must not contain spaces: \(keyword)")
        }
    }
}
