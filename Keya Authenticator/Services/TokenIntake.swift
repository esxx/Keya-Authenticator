import Foundation

struct OTPAuthParameters {
    var type: TokenType
    var secret: String
    var name: String
    var issuer: String?
    var algorithm: Algorithm
    var digits: Int
    var period: Int?
    var counter: UInt64?
}

enum TokenIntakeError: Error, Equatable {
    case notOTPAuth
    case invalidSecret
    case unsupportedDigits
    case unsupportedPeriod
}

enum TokenIntake {
    static let otpAuthScheme = "otpauth://"
    static let migrationScheme = "otpauth-migration://"

    static func hasScheme(_ string: String, _ scheme: String) -> Bool {
        string.prefix(scheme.count).lowercased() == scheme
    }

    static func parameters(fromOTPAuth uri: String) -> OTPAuthParameters? {
        guard hasScheme(uri, otpAuthScheme),
              let url = URL(string: uri.replacingOccurrences(of: " ", with: "%20")),
              url.scheme?.lowercased() == "otpauth"
        else { return nil }

        let type: TokenType
        switch url.host?.lowercased() {
        case "totp": type = .totp
        case "hotp": type = .hotp
        default: return nil
        }

        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }

        var secret: String?
        var issuer: String?
        var algorithm: Algorithm = .sha1
        var digits = 6
        var period: Int?
        var counter: UInt64?
        for item in queryItems {
            switch item.name.lowercased() {
            case "secret": secret = item.value
            case "issuer": issuer = item.value
            case "algorithm": algorithm = algorithmFromString(item.value)
            case "digits": digits = item.value.flatMap(Int.init) ?? digits
            case "period": period = item.value.flatMap(Int.init)
            case "counter": counter = item.value.flatMap(UInt64.init)
            default: break
            }
        }
        guard let secret, !secret.isEmpty else { return nil }

        let label = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name: String
        if let colon = label.range(of: ":") {
            name = label[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            let labelIssuer = label[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
            issuer = issuer ?? (labelIssuer.isEmpty ? nil : labelIssuer)
        } else {
            name = label.trimmingCharacters(in: .whitespaces)
        }

        return OTPAuthParameters(
            type: type, secret: secret, name: name, issuer: issuer,
            algorithm: algorithm, digits: digits, period: period, counter: counter
        )
    }

    static func token(from parameters: OTPAuthParameters) throws -> Token {
        guard let secret = parameters.secret.base32DecodedData, secret.count >= 10 else {
            throw TokenIntakeError.invalidSecret
        }
        guard parameters.digits == 6 || parameters.digits == 8 else { throw TokenIntakeError.unsupportedDigits }
        let period = parameters.type == .totp ? (parameters.period ?? 30) : nil
        guard Token.isSupported(digits: parameters.digits, period: period) else {
            throw TokenIntakeError.unsupportedPeriod
        }
        let issuer = parameters.issuer?.isEmpty == true ? nil : parameters.issuer
        return Token(
            name: parameters.name.isEmpty ? (issuer ?? "Imported Token") : parameters.name,
            issuer: issuer,
            secret: secret, algorithm: parameters.algorithm, digits: parameters.digits,
            type: parameters.type, period: period, counter: parameters.counter
        )
    }

    static func token(fromOTPAuth uri: String) throws -> Token {
        guard let parameters = parameters(fromOTPAuth: uri) else { throw TokenIntakeError.notOTPAuth }
        return try token(from: parameters)
    }

    static func tokens(fromMigration uri: String) -> (tokens: [Token], skipped: Int)? {
        guard let entries = uri.parseMigrationURI() else { return nil }
        let tokens = entries.filter { $0.secret.count >= 10 }.map {
            Token(
                name: $0.name, issuer: $0.issuer, secret: $0.secret, algorithm: $0.algorithm,
                digits: $0.digits, type: $0.type, period: $0.period, counter: $0.counter
            )
        }
        return (tokens, entries.count - tokens.count)
    }
}
