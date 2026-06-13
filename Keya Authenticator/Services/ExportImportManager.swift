import Foundation
import Security
import UniformTypeIdentifiers

@Observable
final class ExportImportManager {
    // MARK: - Types

    struct ImportResult {
        let tokens: [Token]
        let skipped: Int
    }

    // MARK: - Properties

    let tokenStore: TokenStore

    // MARK: - Initialization

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
    }

    // MARK: - Export Methods

    func exportVault() throws -> Data {
        let tokens = tokenStore.tokens
        guard !tokens.isEmpty else {
            throw ExportImportError.noDataToExport
        }

        let exportData = ExportData(
            version: Constants.exportVersion,
            timestamp: Date(),
            tokens: tokens
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(exportData)
    }

    // MARK: - Import Methods

    func parseTokens(from data: Data) throws -> ImportResult {
        if EncryptionService.isEncryptedExport(data) {
            throw ExportImportError.encryptedFileRequiresPassword
        }
        if let ed = try? decodePlaintext(data: data), !ed.tokens.isEmpty {
            return ImportResult(tokens: ed.tokens, skipped: 0)
        }
        var skipped = 0
        if let text = String(data: data, encoding: .utf8),
           text.components(separatedBy: .newlines)
           .contains(where: { $0.hasPrefix("otpauth://") || $0.hasPrefix("otpauth-migration://") }),
           let ed = try? parseGoogleAuthenticatorExport(data: data, skipped: &skipped), !ed.tokens.isEmpty
        {
            return ImportResult(tokens: ed.tokens, skipped: skipped)
        }
        skipped = 0
        if let tokens = try? parseGenericJSON(data: data, skipped: &skipped), !tokens.isEmpty {
            return ImportResult(tokens: tokens, skipped: skipped)
        }
        throw NSError(domain: "Import", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Unrecognised format. Supported: otpauth:// URI list, Aegis/2FAS JSON, Keya Authenticator JSON backup.",
        ])
    }

    // MARK: - Helper Methods

    private func decodePlaintext(data: Data) throws -> ExportData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(ExportData.self, from: data)
        } catch {
            throw ExportImportError.invalidFileFormat
        }
    }

    // MARK: - Google Authenticator Parser

    private func parseGoogleAuthenticatorExport(data: Data, skipped: inout Int) throws -> ExportData {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExportImportError.invalidFileFormat
        }

        let lines = text.components(separatedBy: .newlines)
        var tokens: [Token] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            if trimmedLine.hasPrefix("otpauth://") {
                do {
                    let token = try parseOTPAuthURI(trimmedLine)
                    tokens.append(token)
                } catch {
                    skipped += 1
                }
            } else if trimmedLine.hasPrefix("otpauth-migration://") {
                if let params = trimmedLine.parseMigrationURI() {
                    for p in params {
                        guard p.secret.count >= 10 else { skipped += 1
                            continue
                        }
                        let rawPeriod = p.period ?? 30
                        tokens.append(Token(
                            name: p.name,
                            issuer: p.issuer,
                            secret: p.secret,
                            algorithm: p.algorithm,
                            digits: (p.digits == 6 || p.digits == 8) ? p.digits : 6,
                            type: p.type,
                            period: (rawPeriod >= 15 && rawPeriod <= 300) ? rawPeriod : 30,
                            counter: p.counter
                        ))
                    }
                } else {
                    skipped += 1
                }
            }
        }

        guard !tokens.isEmpty else {
            throw ExportImportError.invalidFileFormat
        }

        return ExportData(
            version: Constants.exportVersion,
            timestamp: Date(),
            tokens: tokens
        )
    }

    // MARK: - Generic JSON Parser

    private func parseGenericJSON(data: Data, skipped: inout Int) throws -> [Token] {
        let rawJSON = try? JSONSerialization.jsonObject(with: data)

        if let json = rawJSON as? [String: Any] {
            var local = 0

            local = 0
            if let t = try? parseAegisFormat(json: json, skipped: &local), !t.isEmpty {
                skipped = local
                return t
            }
            local = 0
            if let t = try? parse2FASFormat(json: json, skipped: &local), !t.isEmpty {
                skipped = local
                return t
            }
            local = 0
            if let t = try? parseLastPassFormat(json: json, skipped: &local), !t.isEmpty {
                skipped = local
                return t
            }
            local = 0
            if let t = try? parseRaivoObjectFormat(json: json, skipped: &local), !t.isEmpty {
                skipped = local
                return t
            }

            if let uris = json["uris"] as? [String] {
                let t = uris.compactMap { try? parseOTPAuthURI($0) }
                if !t.isEmpty { skipped = uris.count - t.count
                    return t
                }
            }
        }

        if let array = rawJSON as? [[String: Any]] {
            var local = 0

            local = 0
            if let t = try? parseRaivoArrayFormat(array: array, skipped: &local), !t.isEmpty {
                skipped = local
                return t
            }
            local = 0
            if let t = try? parseAndOTPFormat(array: array, skipped: &local), !t.isEmpty {
                skipped = local
                return t
            }
        }

        throw ExportImportError.invalidFileFormat
    }

    private func makeExportData(_ tokens: [Token]) -> ExportData {
        ExportData(version: Constants.exportVersion, timestamp: Date(), tokens: tokens)
    }

    // MARK: - Format-Specific Parsers

    private func parseAegisFormat(json: [String: Any], skipped: inout Int) throws -> [Token] {
        guard let db = json["db"] as? [String: Any],
              let entries = db["entries"] as? [[String: Any]]
        else {
            throw ExportImportError.invalidFileFormat
        }

        var tokens: [Token] = []

        for entry in entries {
            guard let name = entry["name"] as? String,
                  let info = entry["info"] as? [String: Any],
                  let secret = info["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else {
                skipped += 1
                continue
            }

            let issuer = entry["issuer"] as? String
            let rawDigits = info["digits"] as? Int ?? 6
            let digits = (rawDigits == 6 || rawDigits == 8) ? rawDigits : 6
            let rawPeriod = info["period"] as? Int ?? 30
            let period = (rawPeriod >= 15 && rawPeriod <= 300) ? rawPeriod : 30
            let counter = info["counter"] as? UInt64 ?? 0
            let algorithm = algorithmFrom(string: info["algo"] as? String)
            let typeStr = ((entry["type"] as? String) ?? "totp").lowercased()
            let tokenType: TokenType = typeStr == "hotp" ? .hotp : .totp

            let token = Token(
                name: name,
                issuer: issuer,
                secret: secretData,
                algorithm: algorithm,
                digits: digits,
                type: tokenType,
                period: tokenType == .totp ? period : nil,
                counter: tokenType == .hotp ? counter : nil
            )

            tokens.append(token)
        }

        return tokens
    }

    private func parse2FASFormat(json: [String: Any], skipped: inout Int) throws -> [Token] {
        guard let services = json["services"] as? [[String: Any]] else {
            throw ExportImportError.invalidFileFormat
        }

        var tokens: [Token] = []

        for service in services {
            guard let serviceName = service["name"] as? String,
                  let secret = service["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else {
                skipped += 1
                continue
            }

            let otp = service["otp"] as? [String: Any]

            let issuer = service["issuer"] as? String ?? otp?["issuer"] as? String ?? serviceName
            let name = otp?["account"] as? String ?? otp?["label"] as? String ?? serviceName
            let rawDigits = otp?["digits"] as? Int ?? service["digits"] as? Int ?? 6
            let digits = (rawDigits == 6 || rawDigits == 8) ? rawDigits : 6
            let rawPeriod = otp?["period"] as? Int ?? service["period"] as? Int ?? 30
            let period = (rawPeriod >= 15 && rawPeriod <= 300) ? rawPeriod : 30
            let algorithmStr = otp?["algorithm"] as? String ?? service["algorithm"] as? String
            let algorithm = algorithmFrom(string: algorithmStr)
            let typeStr = ((otp?["tokenType"] as? String) ?? (service["tokenType"] as? String) ?? "TOTP").uppercased()
            let tokenType: TokenType = typeStr == "HOTP" ? .hotp : .totp
            let counter = otp?["counter"] as? UInt64 ?? service["counter"] as? UInt64 ?? 0

            let token = Token(
                name: name,
                issuer: issuer,
                secret: secretData,
                algorithm: algorithm,
                digits: digits,
                type: tokenType,
                period: tokenType == .totp ? period : nil,
                counter: tokenType == .hotp ? counter : nil
            )

            tokens.append(token)
        }

        return tokens
    }

    // MARK: - andOTP Parser (root array, fields optional with defaults)

    private func parseAndOTPFormat(array: [[String: Any]], skipped: inout Int) throws -> [Token] {
        guard array.contains(where: { $0["secret"] is String }) else {
            throw ExportImportError.invalidFileFormat
        }
        var tokens: [Token] = []
        for entry in array {
            guard let secret = entry["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }
            let name = (entry["label"] as? String) ?? "Imported Token"
            let issuer = entry["issuer"] as? String
            let rawDigits = (entry["digits"] as? Int) ?? 6
            let digits = (rawDigits == 6 || rawDigits == 8) ? rawDigits : 6
            let rawPeriod = (entry["period"] as? Int) ?? 30
            let period = (rawPeriod >= 15 && rawPeriod <= 300) ? rawPeriod : 30
            let counter = (entry["counter"] as? UInt64) ?? 0
            let typeStr = ((entry["type"] as? String) ?? "TOTP").uppercased()
            let type: TokenType = typeStr == "HOTP" ? .hotp : .totp
            let algorithm = algorithmFrom(string: entry["algorithm"] as? String)
            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: type,
                period: type == .totp ? period : nil,
                counter: type == .hotp ? counter : nil
            ))
        }
        return tokens
    }

    // MARK: - LastPass Parser (dict root, "accounts" key, always TOTP)

    private func parseLastPassFormat(json: [String: Any], skipped: inout Int) throws -> [Token] {
        guard let accounts = json["accounts"] as? [[String: Any]] else {
            throw ExportImportError.invalidFileFormat
        }
        var tokens: [Token] = []
        for entry in accounts {
            guard let secret = entry["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }
            let issuer = entry["issuerName"] as? String
            let name = (entry["userName"] as? String) ?? issuer ?? "Imported Token"
            let rawDigits = (entry["digits"] as? Int) ?? 6
            let digits = (rawDigits == 6 || rawDigits == 8) ? rawDigits : 6
            let rawPeriod = (entry["timeStep"] as? Int) ?? 30
            let period = (rawPeriod >= 15 && rawPeriod <= 300) ? rawPeriod : 30
            let algorithm = algorithmFrom(string: entry["algorithm"] as? String)
            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: .totp, period: period
            ))
        }
        return tokens
    }

    // MARK: - Raivo Parsers (all numeric fields are strings)

    private func parseRaivoArrayFormat(array: [[String: Any]], skipped: inout Int) throws -> [Token] {
        guard array.contains(where: { $0["kind"] is String }) else {
            throw ExportImportError.invalidFileFormat
        }
        return raivoTokens(from: array, skipped: &skipped)
    }

    private func parseRaivoObjectFormat(json: [String: Any], skipped: inout Int) throws -> [Token] {
        let entries = json.values.compactMap { $0 as? [String: Any] }
        guard entries.contains(where: { $0["kind"] is String }) else {
            throw ExportImportError.invalidFileFormat
        }
        return raivoTokens(from: entries, skipped: &skipped)
    }

    private func raivoTokens(from entries: [[String: Any]], skipped: inout Int) -> [Token] {
        var tokens: [Token] = []
        for entry in entries {
            guard let secret = entry["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }
            let issuer = entry["issuer"] as? String
            let name = (entry["account"] as? String) ?? issuer ?? "Imported Token"
            let rawDigits = Int(entry["digits"] as? String ?? "") ?? 6
            let digits = (rawDigits == 6 || rawDigits == 8) ? rawDigits : 6
            let rawPeriod = Int(entry["timer"] as? String ?? "") ?? 30
            let period = (rawPeriod >= 15 && rawPeriod <= 300) ? rawPeriod : 30
            let counter = UInt64(entry["counter"] as? String ?? "") ?? 0
            let typeStr = ((entry["kind"] as? String) ?? "TOTP").uppercased()
            let type: TokenType = typeStr == "HOTP" ? .hotp : .totp
            let algorithm = algorithmFrom(string: entry["algorithm"] as? String)
            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: type,
                period: type == .totp ? period : nil,
                counter: type == .hotp ? counter : nil
            ))
        }
        return tokens
    }

    // MARK: - Shared helpers

    private func algorithmFrom(string: String?) -> Algorithm {
        switch (string ?? "").uppercased() {
        case "SHA256": return .sha256
        case "SHA512": return .sha512
        default: return .sha1
        }
    }

    // MARK: - OTP Auth URI Parser

    func parseOTPAuthURI(_ uriString: String) throws -> Token {
        let schemePrefix = "otpauth://"
        guard uriString.lowercased().hasPrefix(schemePrefix) else {
            throw ExportImportError.invalidFileFormat
        }
        let safeURIString = uriString.replacingOccurrences(of: " ", with: "%20")

        guard let url = URL(string: safeURIString) else {
            throw ExportImportError.invalidFileFormat
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ExportImportError.invalidFileFormat
        }

        let type: TokenType
        switch url.host?.lowercased() {
        case "totp":
            type = .totp
        case "hotp":
            type = .hotp
        default:
            throw ExportImportError.invalidFileFormat
        }

        guard let queryItems = components.queryItems else {
            throw ExportImportError.invalidFileFormat
        }

        var secret: String?
        var issuer: String?
        var algorithm: Algorithm = .sha1
        var digits = 6
        var period: Int? = nil
        var counter: UInt64? = nil

        for item in queryItems {
            switch item.name.lowercased() {
            case "secret":
                secret = item.value
            case "issuer":
                issuer = item.value
            case "algorithm":
                if let value = item.value?.uppercased() {
                    switch value {
                    case "SHA256":
                        algorithm = .sha256
                    case "SHA512":
                        algorithm = .sha512
                    default:
                        algorithm = .sha1
                    }
                }
            case "digits":
                if let value = item.value, let intValue = Int(value) {
                    digits = intValue
                }
            case "period":
                if let value = item.value, let intValue = Int(value) {
                    period = intValue
                }
            case "counter":
                if let value = item.value, let intValue = UInt64(value) {
                    counter = intValue
                }
            default:
                break
            }
        }

        guard let secret, !secret.isEmpty,
              let secretData = secret.base32DecodedData,
              secretData.count >= 10
        else {
            throw ExportImportError.invalidFileFormat
        }

        let label = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decodedLabel = label

        let name: String
        let finalIssuer: String?

        if decodedLabel.contains(":") {
            let parts = decodedLabel.split(separator: ":", maxSplits: 1)
            let labelIssuer = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let labelName = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            finalIssuer = issuer ?? (labelIssuer.isEmpty ? nil : labelIssuer)

            name = labelName.isEmpty ? (labelIssuer.isEmpty ? "Imported Token" : labelIssuer) : labelName
        } else {
            name = decodedLabel.isEmpty ? "Imported Token" : decodedLabel
            finalIssuer = issuer
        }

        if type == .totp {
            let p = period ?? 30
            period = (p >= 15 && p <= 300) ? p : 30
            counter = nil
        } else {
            period = nil
            counter = counter ?? 0
        }

        if digits != 6, digits != 8 {
            digits = 6
        }

        return Token(
            name: name,
            issuer: finalIssuer,
            secret: secretData,
            algorithm: algorithm,
            digits: digits,
            type: type,
            period: period,
            counter: counter
        )
    }
}

// MARK: - Supporting Types

private struct ExportData: Codable {
    let version: Int
    let timestamp: Date
    let tokens: [Token]
}

// MARK: - Encrypted Export / Import

extension ExportImportManager {
    func exportVaultEncrypted(password: String) throws -> Data {
        let plaintext = try exportVault()
        return try EncryptionService.encrypt(plaintext, password: password)
    }

    func parseEncryptedTokens(from data: Data, password: String) throws -> ImportResult {
        let plaintext = try EncryptionService.decrypt(data, password: password)
        return try parseTokens(from: plaintext)
    }
}

// MARK: - ExportFormat Implementation

extension ExportImportManager {
    enum ExportFormat: Hashable {
        case plaintext

        var fileExtension: String {
            "json"
        }

        var mimeType: String {
            "application/json"
        }

        var contentType: UTType {
            .json
        }
    }
}

// MARK: - ExportImportError

enum ExportImportError: LocalizedError {
    case invalidFileFormat
    case fileReadError
    case fileWriteError
    case unsupportedFormat
    case noDataToExport
    case encryptedFileRequiresPassword
    case encryptionFailed
    case passwordTooShort
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .invalidFileFormat: return NSLocalizedString(
                "This file couldn't be imported. Make sure it's a valid backup from Aegis, 2FAS, andOTP, Raivo, LastPass, or Keya Authenticator.",
                comment: ""
            )
        case .fileReadError: return NSLocalizedString(
                "The file couldn't be read. Try selecting it again.",
                comment: ""
            )
        case .fileWriteError: return NSLocalizedString(
                "The backup couldn't be saved. Check your available storage and try again.",
                comment: ""
            )
        case .unsupportedFormat: return NSLocalizedString(
                "This file format isn't supported. Supported formats: Aegis, 2FAS, andOTP, Raivo, LastPass, Keya Authenticator.",
                comment: ""
            )
        case .noDataToExport: return NSLocalizedString(
                "There are no tokens to export. Add at least one token first.",
                comment: ""
            )
        case .encryptedFileRequiresPassword: return NSLocalizedString(
                "This backup is encrypted. Enter the password you set when exporting it.",
                comment: ""
            )
        case .encryptionFailed: return NSLocalizedString(
                "The backup couldn't be encrypted. Please try again.",
                comment: ""
            )
        case .passwordTooShort: return NSLocalizedString(
                "Password must be at least 8 characters.",
                comment: ""
            )
        case .wrongPassword: return NSLocalizedString(
                "Incorrect password. Please check your password and try again.",
                comment: ""
            )
        }
    }
}

// MARK: - Constants

extension ExportImportManager {
    private enum Constants {
        static let exportVersion = 1
    }
}
