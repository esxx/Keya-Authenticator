import Foundation

// MARK: - Base32 Decoding (RFC 4648)

extension String {
    var base32DecodedData: Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let cleaned = uppercased().filter { !$0.isWhitespace && $0 != "=" }
        guard !cleaned.isEmpty else { return Data() }

        var bits = 0
        var value = 0
        var bytes = [UInt8]()

        for char in cleaned {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let position = alphabet.distance(from: alphabet.startIndex, to: index)
            value = (value << 5) | position
            bits += 5
            while bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return Data(bytes)
    }

    var isValidBase32: Bool {
        base32DecodedData != nil
    }
}
