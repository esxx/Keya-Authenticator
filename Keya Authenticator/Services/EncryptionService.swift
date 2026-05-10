import CommonCrypto
import CryptoKit
import Foundation
import Security

// MARK: - Encrypted Backup Container

struct EncryptedExportFile: Codable {
    let version: Int
    let encryption: String
    let kdf: String
    let iterations: Int
    let salt: Data
    let ciphertext: Data
}

// MARK: - Encryption Service

enum EncryptionService {
    static let kdfIterations = 100_000
    private static let saltByteCount = 32

    // MARK: - Public Interface

    static func isEncryptedExport(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        // Detect by the encryption algorithm field, not the version number.
        // This correctly recognises future format versions without modification.
        return (json["encryption"] as? String) == "AES-256-GCM"
    }

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw ExportImportError.encryptionFailed }

        let salt = try randomBytes(count: saltByteCount)
        let key = try deriveKey(password: password, salt: salt, iterations: kdfIterations)
        let symmetricKey = SymmetricKey(data: key)

        guard let sealedBox = try? AES.GCM.seal(plaintext, using: symmetricKey),
              let combined = sealedBox.combined
        else { throw ExportImportError.encryptionFailed }

        let container = EncryptedExportFile(
            version: 2,
            encryption: "AES-256-GCM",
            kdf: "PBKDF2-HMAC-SHA256",
            iterations: kdfIterations,
            salt: salt,
            ciphertext: combined
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(container)
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        let container: EncryptedExportFile
        do {
            container = try decoder.decode(EncryptedExportFile.self, from: data)
        } catch {
            throw ExportImportError.invalidFileFormat
        }

        // Use a switch so future format versions can be handled without touching the
        // existing v2 branch. Adding v3 means adding a new case, not mutating the guard.
        switch container.version {
        case 2:
            guard container.encryption == "AES-256-GCM",
                  container.kdf == "PBKDF2-HMAC-SHA256"
            else { throw ExportImportError.unsupportedFormat }

            let key = try deriveKey(
                password: password,
                salt: container.salt,
                iterations: container.iterations
            )
            let symmetricKey = SymmetricKey(data: key)

            do {
                let sealedBox = try AES.GCM.SealedBox(combined: container.ciphertext)
                return try AES.GCM.open(sealedBox, using: symmetricKey)
            } catch {
                throw ExportImportError.wrongPassword
            }

        default:
            throw ExportImportError.unsupportedFormat
        }
    }

    // MARK: - Private Helpers

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> Data {
        guard let passwordData = password.data(using: .utf8) else {
            throw ExportImportError.encryptionFailed
        }
        var derivedKey = Data(count: 32)
        let status: Int32 = derivedKey.withUnsafeMutableBytes { keyPtr in
            passwordData.withUnsafeBytes { pwPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress, passwordData.count,
                        saltPtr.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        keyPtr.baseAddress, 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ExportImportError.encryptionFailed }
        return derivedKey
    }

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { ptr -> OSStatus in
            guard let baseAddress = ptr.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else { throw ExportImportError.encryptionFailed }
        return data
    }
}
