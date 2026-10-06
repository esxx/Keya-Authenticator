import Foundation

// MARK: - Parser protocol

protocol TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult
}

// MARK: - Shared helpers

func algorithmFromString(_ string: String?) -> Algorithm {
    switch (string ?? "").uppercased() {
    case "SHA256": return .sha256
    case "SHA512": return .sha512
    default: return .sha1
    }
}

func tokenTypeFromString(_ string: String?) -> TokenType? {
    switch (string ?? "TOTP").uppercased() {
    case "TOTP": return .totp
    case "HOTP": return .hotp
    default: return nil
    }
}

// MARK: - Keya plaintext adapter

struct KeyaPlaintextParser: TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(KeyaBackupFile.self, from: data), !file.tokens.isEmpty else {
            throw ExportImportError.unsupportedFormat
        }
        let tokens = file.tokens.compactMap(\.supportedToken)
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: file.tokens.count - tokens.count)
    }
}

private struct KeyaBackupFile: Decodable {
    let version: Int
    let timestamp: Date
    let tokens: [Entry]

    struct Entry: Decodable {
        let supportedToken: Token?

        private enum RawKeys: String, CodingKey {
            case type, digits, period
        }

        init(from decoder: Decoder) throws {
            guard let raw = try? decoder.container(keyedBy: RawKeys.self),
                  let type = try? raw.decode(TokenType.self, forKey: .type),
                  let digits = try? raw.decode(Int.self, forKey: .digits),
                  Token.isSupported(
                      digits: digits,
                      period: type == .totp ? (try? raw.decodeIfPresent(Int.self, forKey: .period)) ?? 30 : nil
                  )
            else {
                supportedToken = nil
                return
            }
            supportedToken = try? Token(from: decoder)
        }
    }
}

// MARK: - Aegis adapter

struct AegisParser: TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let db = json["db"] as? [String: Any],
              let entries = db["entries"] as? [[String: Any]]
        else { throw ExportImportError.unsupportedFormat }

        var tokens: [Token] = []
        var skipped = 0
        for entry in entries {
            guard let name = entry["name"] as? String,
                  let info = entry["info"] as? [String: Any],
                  let secret = info["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }

            let issuer = entry["issuer"] as? String
            let digits = info["digits"] as? Int ?? 6
            let period = info["period"] as? Int ?? 30
            let counter = info["counter"] as? UInt64 ?? 0
            let algorithm = algorithmFromString(info["algo"] as? String)
            guard let tokenType = tokenTypeFromString(entry["type"] as? String),
                  Token.isSupported(digits: digits, period: tokenType == .totp ? period : nil)
            else { skipped += 1
                continue
            }

            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: tokenType,
                period: tokenType == .totp ? period : nil,
                counter: tokenType == .hotp ? counter : nil
            ))
        }
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: skipped)
    }
}

// MARK: - 2FAS adapter

struct TwoFASParser: TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let services = json["services"] as? [[String: Any]]
        else { throw ExportImportError.unsupportedFormat }

        var tokens: [Token] = []
        var skipped = 0
        for service in services {
            guard let serviceName = service["name"] as? String,
                  let secret = service["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }

            let otp = service["otp"] as? [String: Any]
            let issuer = service["issuer"] as? String ?? otp?["issuer"] as? String ?? serviceName
            let name = otp?["account"] as? String ?? otp?["label"] as? String ?? serviceName
            let digits = otp?["digits"] as? Int ?? service["digits"] as? Int ?? 6
            let period = otp?["period"] as? Int ?? service["period"] as? Int ?? 30
            let algorithm = algorithmFromString(otp?["algorithm"] as? String ?? service["algorithm"] as? String)
            let counter = otp?["counter"] as? UInt64 ?? service["counter"] as? UInt64 ?? 0
            guard let tokenType = tokenTypeFromString(otp?["tokenType"] as? String ?? service["tokenType"] as? String),
                  Token.isSupported(digits: digits, period: tokenType == .totp ? period : nil)
            else { skipped += 1
                continue
            }

            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: tokenType,
                period: tokenType == .totp ? period : nil,
                counter: tokenType == .hotp ? counter : nil
            ))
        }
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: skipped)
    }
}

// MARK: - LastPass adapter

struct LastPassParser: TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = json["accounts"] as? [[String: Any]]
        else { throw ExportImportError.unsupportedFormat }

        var tokens: [Token] = []
        var skipped = 0
        for entry in accounts {
            guard let secret = entry["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }

            let issuer = entry["issuerName"] as? String
            let name = (entry["userName"] as? String) ?? issuer ?? "Imported Token"
            let digits = (entry["digits"] as? Int) ?? 6
            let period = (entry["timeStep"] as? Int) ?? 30
            let algorithm = algorithmFromString(entry["algorithm"] as? String)
            guard Token.isSupported(digits: digits, period: period) else { skipped += 1
                continue
            }
            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: .totp, period: period
            ))
        }
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: skipped)
    }
}

// MARK: - andOTP adapter

struct AndOTPParser: TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              array.contains(where: { $0["secret"] is String })
        else { throw ExportImportError.unsupportedFormat }

        var tokens: [Token] = []
        var skipped = 0
        for entry in array {
            guard let secret = entry["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }

            let name = (entry["label"] as? String) ?? "Imported Token"
            let issuer = entry["issuer"] as? String
            let digits = (entry["digits"] as? Int) ?? 6
            let period = (entry["period"] as? Int) ?? 30
            let counter = (entry["counter"] as? UInt64) ?? 0
            let algorithm = algorithmFromString(entry["algorithm"] as? String)
            guard let type = tokenTypeFromString(entry["type"] as? String),
                  Token.isSupported(digits: digits, period: type == .totp ? period : nil)
            else { skipped += 1
                continue
            }
            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: type,
                period: type == .totp ? period : nil,
                counter: type == .hotp ? counter : nil
            ))
        }
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: skipped)
    }
}

// MARK: - Raivo adapter

struct RaivoParser: TokenImportParser {
    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        let raw = try? JSONSerialization.jsonObject(with: data)

        let entries: [[String: Any]]
        if let array = raw as? [[String: Any]], array.contains(where: { $0["kind"] is String }) {
            entries = array
        } else if let dict = raw as? [String: Any] {
            let vals = dict.values.compactMap { $0 as? [String: Any] }
            guard vals.contains(where: { $0["kind"] is String }) else {
                throw ExportImportError.unsupportedFormat
            }
            entries = vals
        } else {
            throw ExportImportError.unsupportedFormat
        }

        var tokens: [Token] = []
        var skipped = 0
        for entry in entries {
            guard let secret = entry["secret"] as? String,
                  let secretData = secret.base32DecodedData,
                  secretData.count >= 10
            else { skipped += 1
                continue
            }

            let issuer = entry["issuer"] as? String
            let name = (entry["account"] as? String) ?? issuer ?? "Imported Token"
            let digits = Int(entry["digits"] as? String ?? "") ?? 6
            let period = Int(entry["timer"] as? String ?? "") ?? 30
            let counter = UInt64(entry["counter"] as? String ?? "") ?? 0
            let algorithm = algorithmFromString(entry["algorithm"] as? String)
            guard let type = tokenTypeFromString(entry["kind"] as? String),
                  Token.isSupported(digits: digits, period: type == .totp ? period : nil)
            else { skipped += 1
                continue
            }
            tokens.append(Token(
                name: name, issuer: issuer, secret: secretData,
                algorithm: algorithm, digits: digits, type: type,
                period: type == .totp ? period : nil,
                counter: type == .hotp ? counter : nil
            ))
        }
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: skipped)
    }
}

// MARK: - OTPAuth URI adapter

struct OTPAuthURIParser: TokenImportParser {
    private let parseURI: (String) throws -> Token

    init(parseURI: @escaping (String) throws -> Token) {
        self.parseURI = parseURI
    }

    func parse(from data: Data) throws -> ExportImportManager.ImportResult {
        guard let text = String(data: data, encoding: .utf8),
              text.components(separatedBy: .newlines)
              .contains(where: { $0.hasPrefix("otpauth://") || $0.hasPrefix("otpauth-migration://") })
        else { throw ExportImportError.unsupportedFormat }

        let lines = text.components(separatedBy: .newlines)
        var tokens: [Token] = []
        var skipped = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("otpauth://") {
                if let token = try? parseURI(trimmed) {
                    tokens.append(token)
                } else {
                    skipped += 1
                }
            } else if trimmed.hasPrefix("otpauth-migration://") {
                if let params = trimmed.parseMigrationURI() {
                    for p in params {
                        guard p.secret.count >= 10 else { skipped += 1
                            continue
                        }
                        let rawPeriod = p.period ?? 30
                        tokens.append(Token(
                            name: p.name, issuer: p.issuer, secret: p.secret,
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
        guard !tokens.isEmpty else { throw ExportImportError.invalidFileFormat }
        return ExportImportManager.ImportResult(tokens: tokens, skipped: skipped)
    }
}
