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
        let parsers: [TokenImportParser] = [
            KeyaPlaintextParser(),
            OTPAuthURIParser(parseURI: parseOTPAuthURI),
            AegisParser(),
            TwoFASParser(),
            LastPassParser(),
            RaivoParser(),
            AndOTPParser(),
        ]
        for parser in parsers {
            do {
                return try parser.parse(from: data)
            } catch ExportImportError.unsupportedFormat {
                continue
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uris = json["uris"] as? [String]
        {
            let tokens = uris.compactMap { try? parseOTPAuthURI($0) }
            if !tokens.isEmpty {
                return ImportResult(tokens: tokens, skipped: uris.count - tokens.count)
            }
        }
        throw NSError(domain: "Import", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Unrecognised format. Supported: otpauth:// URI list, Aegis/2FAS JSON, Keya Authenticator JSON backup.",
        ])
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
