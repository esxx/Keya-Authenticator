import Foundation

// MARK: - OTP Auth URI Parsing

extension String {
    func extractOTPParameters() -> (
        type: TokenType,
        secret: String,
        name: String,
        issuer: String?,
        algorithm: Algorithm,
        digits: Int,
        period: Int?,
        counter: UInt64?
    )? {
        guard hasPrefix("otpauth://") else { return nil }

        // Only replace raw spaces — some apps emit labels with literal spaces that are
        // not valid in URL syntax. Re-encoding the entire label would double-encode
        // already-encoded sequences like %40 → %2540 (since % is not in urlPathAllowed).
        let safeURIString = replacingOccurrences(of: " ", with: "%20")

        guard let url = URL(string: safeURIString), url.scheme == "otpauth" else { return nil }

        let tokenType: TokenType
        switch url.host?.lowercased() {
        case "totp": tokenType = .totp
        case "hotp": tokenType = .hotp
        default: return nil
        }

        let label = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }

        var secret: String?
        var issuer: String?
        var algorithm: Algorithm = .sha1
        var digits = 6
        var period: Int?
        var counter: UInt64?

        // URLComponents.queryItems automatically percent-decodes both names and values
        // (RFC 3986 §3.4), so item.value is already the decoded string — no extra
        // removingPercentEncoding call is needed here.
        for item in queryItems {
            switch item.name.lowercased() {
            case "secret": secret = item.value
            case "issuer": issuer = item.value
            case "algorithm":
                switch item.value?.uppercased() {
                case "SHA256": algorithm = .sha256
                case "SHA512": algorithm = .sha512
                default: algorithm = .sha1
                }
            case "digits":
                if let v = item.value, let n = Int(v) { digits = n }
            case "period":
                if let v = item.value, let n = Int(v) { period = n }
            case "counter":
                if let v = item.value, let n = UInt64(v) { counter = n }
            default: break
            }
        }

        guard let secret, !secret.isEmpty else { return nil }

        var name: String
        if let colonRange = label.range(of: ":") {
            name = String(label[colonRange.upperBound...])
            if issuer == nil { issuer = String(label[..<colonRange.lowerBound]) }
        } else {
            name = label
        }

        return (tokenType, secret, name, issuer, algorithm, digits, period, counter)
    }

    var isValidOTPSecret: Bool {
        guard let data = base32DecodedData else { return false }
        return data.count >= 10
    }
}

// MARK: - Google Authenticator Migration URI Parsing

extension String {
    func parseMigrationURI() -> [(
        type: TokenType,
        secret: Data,
        name: String,
        issuer: String?,
        algorithm: Algorithm,
        digits: Int,
        period: Int?,
        counter: UInt64?
    )]? {
        guard hasPrefix("otpauth-migration://") else { return nil }

        let encoded: String
        if let url = URL(string: self),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let val = components.queryItems?.first(where: { $0.name == "data" })?.value
        {
            encoded = val
        } else if let safe = addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: safe),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let val = components.queryItems?.first(where: { $0.name == "data" })?.value
        {
            encoded = val
        } else {
            return nil
        }

        // `encoded` is already percent-decoded by URLComponents.queryItems — no further decoding needed.
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = base64.count % 4
        if rem > 0 { base64 += String(repeating: "=", count: 4 - rem) }

        guard let protoData = Data(base64Encoded: base64) else { return nil }
        return String.parseMigrationPayload(protoData)
    }
}

// MARK: - Protobuf Decoding (hand-rolled, no dependency)

private extension String {
    static func parseMigrationPayload(_ data: Data) -> [(
        type: TokenType,
        secret: Data,
        name: String,
        issuer: String?,
        algorithm: Algorithm,
        digits: Int,
        period: Int?,
        counter: UInt64?
    )]? {
        var tokens: [(
            type: TokenType, secret: Data, name: String, issuer: String?,
            algorithm: Algorithm, digits: Int, period: Int?, counter: UInt64?
        )] = []
        var pos = 0
        while pos < data.count {
            guard let tag = protoReadVarint(data, pos: &pos) else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            if fieldNumber == 1, wireType == 2 {
                guard let length = protoReadVarint(data, pos: &pos),
                      length <= UInt64(Int.max) else { break }
                let end = pos + Int(length)
                guard end <= data.count else { break }
                if let params = parseOtpParameters(Data(data[pos ..< end])) {
                    tokens.append(params)
                }
                pos = end
            } else {
                guard protoSkipField(data, pos: &pos, wireType: wireType) else { break }
            }
        }
        return tokens.isEmpty ? nil : tokens
    }

    static func parseOtpParameters(_ data: Data) -> (
        type: TokenType, secret: Data, name: String, issuer: String?,
        algorithm: Algorithm, digits: Int, period: Int?, counter: UInt64?
    )? {
        var secret: Data?
        var name = "Imported Token"
        var issuer: String?
        var algorithm: Algorithm = .sha1
        var digits = 6
        var otpType = 2 // 2 = TOTP
        var counter: UInt64 = 0
        var pos = 0

        while pos < data.count {
            guard let tag = protoReadVarint(data, pos: &pos) else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            switch (fieldNumber, wireType) {
            case (1, 2):
                guard let len = protoReadVarint(data, pos: &pos), len <= UInt64(Int.max) else { return nil }
                let end = pos + Int(len)
                guard end <= data.count else { return nil }
                secret = Data(data[pos ..< end])
                pos = end
            case (2, 2):
                guard let len = protoReadVarint(data, pos: &pos), len <= UInt64(Int.max) else { return nil }
                let end = pos + Int(len)
                guard end <= data.count else { return nil }
                name = String(data: data[pos ..< end], encoding: .utf8) ?? name
                pos = end
            case (3, 2):
                guard let len = protoReadVarint(data, pos: &pos), len <= UInt64(Int.max) else { return nil }
                let end = pos + Int(len)
                guard end <= data.count else { return nil }
                issuer = String(data: data[pos ..< end], encoding: .utf8)
                pos = end
            case (4, 0):
                guard let val = protoReadVarint(data, pos: &pos) else { return nil }
                switch val { case 2: algorithm = .sha256
                case 3: algorithm = .sha512
                default: algorithm = .sha1 }
            case (5, 0):
                guard let val = protoReadVarint(data, pos: &pos) else { return nil }
                digits = (val == 2) ? 8 : 6
            case (6, 0):
                guard let val = protoReadVarint(data, pos: &pos) else { return nil }
                otpType = Int(val)
            case (7, 0):
                guard let val = protoReadVarint(data, pos: &pos) else { return nil }
                counter = val
            default:
                guard protoSkipField(data, pos: &pos, wireType: wireType) else { return nil }
            }
        }

        guard let secretData = secret else { return nil }
        let tokenType: TokenType = (otpType == 1) ? .hotp : .totp
        return (
            tokenType, secretData, name, issuer, algorithm, digits,
            tokenType == .totp ? 30 : nil,
            tokenType == .hotp ? counter : nil
        )
    }

    static func protoReadVarint(_ data: Data, pos: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift = 0
        while pos < data.count {
            let byte = data[pos]
            pos += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { return nil }
        }
        return nil
    }

    static func protoSkipField(_ data: Data, pos: inout Int, wireType: Int) -> Bool {
        switch wireType {
        case 0: return protoReadVarint(data, pos: &pos) != nil
        case 1: guard pos + 8 <= data.count else { return false }
            pos += 8
            return true
        case 2:
            guard let len = protoReadVarint(data, pos: &pos),
                  len <= UInt64(Int.max),
                  pos + Int(len) <= data.count else { return false }
            pos += Int(len)
            return true
        case 5: guard pos + 4 <= data.count else { return false }
            pos += 4
            return true
        default: return false
        }
    }
}
