import Foundation

// MARK: - Base32 Encoding

extension Data {
    var base32EncodedString: String {
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

        var result = ""
        var buffer = 0
        var bitsLeft = 0

        for byte in self {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8

            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 0x1F
                result.append(base32Alphabet[base32Alphabet.index(base32Alphabet.startIndex, offsetBy: index)])
                bitsLeft -= 5
            }
        }

        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            result.append(base32Alphabet[base32Alphabet.index(base32Alphabet.startIndex, offsetBy: index)])
        }

        let paddingCount = (8 - (result.count % 8)) % 8
        result += String(repeating: "=", count: paddingCount)

        return result
    }
}
