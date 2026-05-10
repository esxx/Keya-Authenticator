import Foundation

enum TokenError: LocalizedError, Equatable {
    case invalidSecret(String)
    case invalidDigits(String)
    case invalidPeriod(String)
    case invalidCounter(String)
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSecret(message): return message
        case let .invalidDigits(message): return message
        case let .invalidPeriod(message): return message
        case let .invalidCounter(message): return message
        case let .keychainError(message): return message
        }
    }
}

extension TokenError {
    static let invalidBase32 = TokenError.invalidSecret("Invalid Base32 encoding")
}
