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
            OTPAuthURIParser(),
            AegisParser(),
            TwoFASParser(),
            LastPassParser(),
            RaivoParser(),
            AndOTPParser(),
        ]
        var recognisedFormatError: Error?
        for parser in parsers {
            do {
                return try parser.parse(from: data)
            } catch ExportImportError.unsupportedFormat {
                continue
            } catch {
                recognisedFormatError = recognisedFormatError ?? error
                continue
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let uris = json["uris"] as? [String]
        {
            let tokens = uris.compactMap { try? TokenIntake.token(fromOTPAuth: $0) }
            if !tokens.isEmpty {
                return ImportResult(tokens: tokens, skipped: uris.count - tokens.count)
            }
        }
        if let recognisedFormatError {
            throw recognisedFormatError
        }
        throw ExportImportError.unsupportedFormat
    }
}

// MARK: - Supporting Types

private struct ExportData: Codable {
    let version: Int
    let timestamp: Date
    let tokens: [Token]
}

// MARK: - ExportFormat Implementation

extension ExportImportManager {
    enum ExportFormat: Hashable {
        case plaintext

        var contentType: UTType {
            .json
        }
    }
}

// MARK: - ExportImportError

nonisolated enum ExportImportError: LocalizedError {
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
