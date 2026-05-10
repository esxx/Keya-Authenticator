import Foundation

enum Algorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

enum TokenType: String, Codable {
    case totp = "TOTP"
    case hotp = "HOTP"

    var displayName: String {
        switch self {
        case .totp: return String(localized: "TOTP")
        case .hotp: return String(localized: "HOTP")
        }
    }
}
