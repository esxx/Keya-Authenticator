import CryptoKit
import Foundation

enum OTPGenerator {
    // MARK: - Constants

    static let defaultTOTPPeriod: Int = 30

    static let defaultDigits: Int = 6

    // MARK: - TOTP Generation (RFC 6238)

    static func generateTOTP(
        secret: Data,
        time: Date = Date(),
        period: Int = defaultTOTPPeriod,
        digits: Int = defaultDigits,
        algorithm: Algorithm = .sha1
    ) throws -> String {
        guard period > 0 else {
            throw TokenError.invalidPeriod("Period must be positive")
        }

        guard digits == 6 || digits == 8 else {
            throw TokenError.invalidDigits("Digits must be 6 or 8")
        }

        let timeInterval = time.timeIntervalSince1970
        let timeCounter = UInt64(timeInterval / Double(period))

        return try generateHOTP(
            secret: secret,
            counter: timeCounter,
            digits: digits,
            algorithm: algorithm
        )
    }

    // MARK: - HOTP Generation (RFC 4226)

    static func generateHOTP(
        secret: Data,
        counter: UInt64,
        digits: Int = defaultDigits,
        algorithm: Algorithm = .sha1
    ) throws -> String {
        guard digits == 6 || digits == 8 else {
            throw TokenError.invalidDigits("Digits must be 6 or 8")
        }

        let hmac = try generateHMAC(secret: secret, counter: counter, algorithm: algorithm)

        let dbc = dynamicBinaryCode(from: hmac)

        let hotpValue = dbc % UInt32(pow(10, Double(digits)))

        return String(format: "%0\(digits)d", hotpValue)
    }

    // MARK: - HMAC Generation

    private static func generateHMAC(
        secret: Data,
        counter: UInt64,
        algorithm: Algorithm
    ) throws -> Data {
        let counterBytes = counter.bigEndianBytes

        switch algorithm {
        case .sha1:
            let key = SymmetricKey(data: secret)
            let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: key)
            return Data(hmac)
        case .sha256:
            let key = SymmetricKey(data: secret)
            let hmac = HMAC<SHA256>.authenticationCode(for: counterBytes, using: key)
            return Data(hmac)
        case .sha512:
            let key = SymmetricKey(data: secret)
            let hmac = HMAC<SHA512>.authenticationCode(for: counterBytes, using: key)
            return Data(hmac)
        }
    }

    // MARK: - Helper Methods

    private static func dynamicBinaryCode(from hmac: Data) -> UInt32 {
        let offset = Int(hmac[hmac.count - 1] & 0x0F)

        let codeBytes = hmac[offset ..< offset + 4]

        var code: UInt32 = 0
        for (index, byte) in codeBytes.enumerated() {
            code |= UInt32(byte) << UInt32(8 * (3 - index))
        }

        return code & 0x7FFF_FFFF
    }
}

// MARK: - Extensions for Helper Types

private extension UInt64 {
    var bigEndianBytes: Data {
        var value = bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

// MARK: - Token Extension for OTP Generation

extension Token {
    func generateCode(time: Date = Date()) throws -> String {
        switch type {
        case .totp:
            guard let period else {
                throw TokenError.invalidPeriod("TOTP token missing period")
            }
            return try OTPGenerator.generateTOTP(
                secret: secret,
                time: time,
                period: period,
                digits: digits,
                algorithm: algorithm
            )
        case .hotp:
            guard let counter else {
                throw TokenError.invalidCounter("HOTP token missing counter")
            }
            return try OTPGenerator.generateHOTP(
                secret: secret,
                counter: counter,
                digits: digits,
                algorithm: algorithm
            )
        }
    }
}
