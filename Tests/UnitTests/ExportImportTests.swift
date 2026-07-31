import XCTest
@testable import Keya_Authenticator

final class ExportImportTests: XCTestCase {

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
        tokenStore = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - Export

    func testExportEmptyVaultThrows() {
        XCTAssertThrowsError(try manager.exportVault()) { error in
            guard let exportError = error as? ExportImportError else {
                return XCTFail("Expected ExportImportError, got \(error)")
            }
            XCTAssertEqual(exportError, .noDataToExport)
        }
    }

    // MARK: - Round-trip

    func testPlaintextRoundTripPreservesFields() throws {
        let secret = "JBSWY3DPEHPK3PXP".base32DecodedData!
        let original = Token(name: "alice@example.com", issuer: "Example",
                             secret: secret, algorithm: .sha1,
                             digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([original])

        let data = try manager.exportVault()
        let imported = try manager.parseTokens(from: data)

        XCTAssertEqual(imported.tokens.count, 1)
        let token = imported.tokens[0]
        XCTAssertEqual(token.name, original.name)
        XCTAssertEqual(token.issuer, original.issuer)
        XCTAssertEqual(token.secret, original.secret)
        XCTAssertEqual(token.algorithm, original.algorithm)
        XCTAssertEqual(token.type, original.type)
        XCTAssertEqual(token.digits, original.digits)
        XCTAssertEqual(token.period, original.period)
    }

    // MARK: - Aegis import

    func testAegisImport() throws {
        let json = """
        {
            "version": 1,
            "header": { "slots": null, "params": null },
            "db": {
                "version": 2,
                "entries": [{
                    "type": "totp",
                    "uuid": "01234567-89ab-cdef-0123-456789abcdef",
                    "name": "alice",
                    "issuer": "AcmeCorp",
                    "note": "",
                    "favorite": false,
                    "icon": null,
                    "info": {
                        "secret": "JBSWY3DPEHPK3PXP",
                        "algo": "SHA1",
                        "digits": 6,
                        "period": 30
                    }
                }]
            }
        }
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "AcmeCorp")
        XCTAssertEqual(result.tokens[0].name, "alice")
        XCTAssertEqual(result.tokens[0].type, .totp)
        XCTAssertEqual(result.tokens[0].digits, 6)
        XCTAssertEqual(result.tokens[0].period, 30)
    }

    // MARK: - 2FAS import

    func testTwoFASImport() throws {
        let json = """
        {
            "services": [{
                "name": "GitHub",
                "secret": "JBSWY3DPEHPK3PXP",
                "serviceTypeID": null,
                "otp": {
                    "label": "user@github.com",
                    "account": "user@github.com",
                    "digits": 6,
                    "counter": 0,
                    "period": 30,
                    "algorithm": "SHA1",
                    "tokenType": "TOTP"
                }
            }]
        }
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "GitHub")
        XCTAssertEqual(result.tokens[0].type, .totp)
    }

    // MARK: - otpauth:// URI list import

    func testURIListImport() throws {
        let list = """
        otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub
        otpauth://totp/Google:user@gmail.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=Google
        """
        let result = try manager.parseTokens(from: list.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 2)
        XCTAssertEqual(result.tokens[0].issuer, "GitHub")
        XCTAssertEqual(result.tokens[1].issuer, "Google")
    }

    // MARK: - Invalid data

    func testGarbageDataThrows() {
        let data = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try manager.parseTokens(from: data))
    }

    // MARK: - andOTP import

    func testAndOTPImport() throws {
        let json = """
        [
            {
                "secret": "JBSWY3DPEHPK3PXP",
                "label": "alice@acme.com",
                "issuer": "AcmeCorp",
                "type": "TOTP",
                "algorithm": "SHA1",
                "digits": 6,
                "period": 30
            }
        ]
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, "alice@acme.com")
        XCTAssertEqual(result.tokens[0].issuer, "AcmeCorp")
        XCTAssertEqual(result.tokens[0].type, .totp)
        XCTAssertEqual(result.tokens[0].digits, 6)
        XCTAssertEqual(result.tokens[0].period, 30)
    }

    func testAndOTPHOTPImport() throws {
        let json = """
        [
            {
                "secret": "JBSWY3DPEHPK3PXP",
                "label": "hotp-account",
                "type": "HOTP",
                "digits": 6,
                "counter": 42
            }
        ]
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].type, .hotp)
        XCTAssertEqual(result.tokens[0].counter, 42)
        XCTAssertNil(result.tokens[0].period, "HOTP tokens must not carry a period")
    }

    // MARK: - LastPass import

    func testLastPassImport() throws {
        let json = """
        {
            "accounts": [
                {
                    "secret": "JBSWY3DPEHPK3PXP",
                    "issuerName": "GitHub",
                    "userName": "user@github.com",
                    "digits": 6,
                    "timeStep": 30,
                    "algorithm": "SHA1"
                }
            ]
        }
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "GitHub")
        XCTAssertEqual(result.tokens[0].name, "user@github.com")
        XCTAssertEqual(result.tokens[0].type, .totp)
        XCTAssertEqual(result.tokens[0].period, 30)
    }

    // MARK: - Raivo import

    func testRaivoArrayImport() throws {
        let json = """
        [
            {
                "secret": "JBSWY3DPEHPK3PXP",
                "account": "alice",
                "issuer": "AcmeCorp",
                "kind": "TOTP",
                "algorithm": "SHA1",
                "digits": "6",
                "timer": "30"
            }
        ]
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1, "Raivo array data must import without throwing")
        XCTAssertEqual(result.tokens[0].issuer, "AcmeCorp")
        XCTAssertEqual(result.tokens[0].type, .totp)
        XCTAssertFalse(result.tokens[0].secret.isEmpty, "Secret must be decoded correctly")
        XCTAssertEqual(result.tokens[0].name, "alice")
    }

    func testRaivoObjectImport() throws {
        let json = """
        {
            "A1B2C3D4-E5F6-7890-ABCD-EF1234567890": {
                "secret": "JBSWY3DPEHPK3PXP",
                "account": "bob",
                "issuer": "Example",
                "kind": "TOTP",
                "algorithm": "SHA256",
                "digits": "8",
                "timer": "60"
            }
        }
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, "bob")
        XCTAssertEqual(result.tokens[0].algorithm, .sha256)
        XCTAssertEqual(result.tokens[0].digits, 8)
        XCTAssertEqual(result.tokens[0].period, 60)
    }

    // MARK: - skipped count

    func testMalformedAegisEntriesIncreasesSkippedCount() throws {
        let json = """
        {
            "db": {
                "entries": [
                    {
                        "name": "valid",
                        "issuer": "Corp",
                        "info": { "secret": "JBSWY3DPEHPK3PXP", "digits": 6, "period": 30 }
                    },
                    {
                        "name": "broken",
                        "issuer": "Corp",
                        "info": { "digits": 6 }
                    }
                ]
            }
        }
        """
        let result = try manager.parseTokens(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.skipped, 1, "Entry missing secret must be counted as skipped")
    }

    func testAllMalformedEntriesThrows() {
        let json = """
        {
            "db": {
                "entries": [
                    { "name": "broken", "info": { "digits": 6 } }
                ]
            }
        }
        """
        XCTAssertThrowsError(try manager.parseTokens(from: json.data(using: .utf8)!))
    }

    // MARK: - Algorithm / digits preservation

    func testSHA256AlgorithmPreservedInRoundTrip() throws {
        let original = Token(name: "SHA256 Token", issuer: "Corp",
                             secret: secret, algorithm: .sha256,
                             digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([original])

        let data = try manager.exportVault()
        let result = try manager.parseTokens(from: data)

        XCTAssertEqual(result.tokens[0].algorithm, .sha256)
    }

    func testEightDigitTokenPreservedInRoundTrip() throws {
        let original = Token(name: "8-digit Token", issuer: "Corp",
                             secret: secret, algorithm: .sha1,
                             digits: 8, type: .totp, period: 30, counter: nil)
        try tokenStore.update([original])

        let data = try manager.exportVault()
        let result = try manager.parseTokens(from: data)

        XCTAssertEqual(result.tokens[0].digits, 8)
    }

    // MARK: - HOTP counter round-trip

    func testHOTPCounterPreservedInRoundTrip() throws {
        let original = Token(name: "HOTP Token", issuer: "Corp",
                             secret: secret, algorithm: .sha1,
                             digits: 6, type: .hotp, period: nil, counter: 99)
        try tokenStore.update([original])

        let data = try manager.exportVault()
        let result = try manager.parseTokens(from: data)

        XCTAssertEqual(result.tokens[0].type, .hotp)
        XCTAssertEqual(result.tokens[0].counter, 99)
        XCTAssertNil(result.tokens[0].period)
    }

    // MARK: - Encrypted export / import

    func testEncryptedRoundTrip() throws {
        let original = Token(name: "Encrypted Token", issuer: "Corp",
                             secret: secret, algorithm: .sha1,
                             digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([original])

        let encryptedData = try manager.exportVaultEncrypted(password: "hunter2x")
        let result = try manager.parseEncryptedTokens(from: encryptedData, password: "hunter2x")

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, original.name)
        XCTAssertEqual(result.tokens[0].secret, original.secret)
    }

    func testEncryptedWrongPasswordThrows() throws {
        let original = Token(name: "Encrypted Token", issuer: "Corp",
                             secret: secret, algorithm: .sha1,
                             digits: 6, type: .totp, period: 30, counter: nil)
        try tokenStore.update([original])

        let encryptedData = try manager.exportVaultEncrypted(password: "correct-password")

        XCTAssertThrowsError(
            try manager.parseEncryptedTokens(from: encryptedData, password: "wrong-password")
        ) { error in
            guard let exportError = error as? ExportImportError else {
                return XCTFail("Expected ExportImportError, got \(error)")
            }
            XCTAssertEqual(exportError, .wrongPassword)
        }
    }

    func testEncryptedEmptyVaultThrows() throws {
        XCTAssertThrowsError(try manager.exportVaultEncrypted(password: "any")) { error in
            guard let exportError = error as? ExportImportError else {
                return XCTFail("Expected ExportImportError, got \(error)")
            }
            XCTAssertEqual(exportError, .noDataToExport)
        }
    }

    // MARK: - Direct adapter tests (seam verification)

    func testAegisParserDirectly() throws {
        let json = """
        {
            "db": {
                "entries": [{
                    "type": "totp",
                    "name": "direct",
                    "issuer": "DirectCorp",
                    "info": { "secret": "JBSWY3DPEHPK3PXP", "algo": "SHA1", "digits": 6, "period": 30 }
                }]
            }
        }
        """
        let result = try AegisParser().parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "DirectCorp")
        XCTAssertEqual(result.skipped, 0)
    }

    func testAegisParserThrowsOnNonAegisData() {
        let data = #"{"services": []}"#.data(using: .utf8)!
        XCTAssertThrowsError(try AegisParser().parse(from: data))
    }

    func testAegisParserCountsSkippedEntries() throws {
        let json = """
        {
            "db": {
                "entries": [
                    { "name": "ok", "issuer": "Corp",
                      "info": { "secret": "JBSWY3DPEHPK3PXP", "digits": 6, "period": 30 } },
                    { "name": "bad", "issuer": "Corp", "info": { "digits": 6 } }
                ]
            }
        }
        """
        let result = try AegisParser().parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.skipped, 1)
    }

    func testTwoFASParserDirectly() throws {
        let json = """
        { "services": [{ "name": "G", "secret": "JBSWY3DPEHPK3PXP",
          "otp": { "account": "u@g.com", "tokenType": "TOTP", "digits": 6, "period": 30 } }] }
        """
        let result = try TwoFASParser().parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].type, .totp)
    }

    func testLastPassParserDirectly() throws {
        let json = """
        { "accounts": [{ "secret": "JBSWY3DPEHPK3PXP", "issuerName": "LP", "userName": "u", "timeStep": 30 }] }
        """
        let result = try LastPassParser().parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "LP")
    }

    func testAndOTPParserDirectly() throws {
        let json = """
        [{ "secret": "JBSWY3DPEHPK3PXP", "label": "andotp-account", "type": "TOTP", "digits": 6, "period": 30 }]
        """
        let result = try AndOTPParser().parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, "andotp-account")
    }

    func testRaivoParserDirectlyArray() throws {
        let json = """
        [{ "secret": "JBSWY3DPEHPK3PXP", "account": "raivo-user", "issuer": "R",
           "kind": "TOTP", "digits": "6", "timer": "30" }]
        """
        let result = try RaivoParser().parse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].name, "raivo-user")
    }

    func testOTPAuthURIParserDirectly() throws {
        let text = "otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
        let parser = OTPAuthURIParser(parseURI: manager.parseOTPAuthURI)
        let result = try parser.parse(from: text.data(using: .utf8)!)
        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].issuer, "GitHub")
    }

    func testOTPAuthURIParserThrowsOnNonURIData() {
        let data = #"{"not": "a uri"}"#.data(using: .utf8)!
        let parser = OTPAuthURIParser(parseURI: manager.parseOTPAuthURI)
        XCTAssertThrowsError(try parser.parse(from: data))
    }

    func testKeyaPlaintextParserThrowsOnNonKeyaData() {
        let data = #"{"services": []}"#.data(using: .utf8)!
        XCTAssertThrowsError(try KeyaPlaintextParser().parse(from: data))
    }
}
