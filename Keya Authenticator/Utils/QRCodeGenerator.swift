import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

@MainActor
final class QRCodeGenerator {
    // MARK: - Cached Context

    private static let cachedContext = CIContext()

    // MARK: - QR Code Generation

    static func generateQRCode(from token: Token) -> UIImage? {
        let uri = generateOTPAuthURI(from: token)
        return generateQRCode(from: uri)
    }

    static func generateQRCode(
        from string: String,
        correctionLevel: String = "H"
    ) -> UIImage? {
        guard !string.isEmpty else { return nil }

        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let scale: CGFloat = 20
        let scaledImage = outputImage
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let qrCGImage = cachedContext.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        let quietZonePixels = Int(4 * scale)
        let totalSize = CGSize(
            width: qrCGImage.width + 2 * quietZonePixels,
            height: qrCGImage.height + 2 * quietZonePixels
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: totalSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: totalSize))
            UIImage(cgImage: qrCGImage).draw(in: CGRect(
                x: quietZonePixels,
                y: quietZonePixels,
                width: qrCGImage.width,
                height: qrCGImage.height
            ))
        }
    }

    // MARK: - OTP Auth URI Generation

    static func generateOTPAuthURI(from token: Token) -> String {
        let typeStr = token.type == .totp ? "totp" : "hotp"

        let rawLabel: String = if let issuer = token.issuer, !issuer.isEmpty {
            "\(issuer):\(token.name)"
        } else {
            token.name
        }
        let label = rawLabel.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? rawLabel

        let queryValueAllowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        func encodeValue(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
        }

        let secret = token.secret.base32EncodedString.filter { $0 != "=" }

        var queryItems = ["secret=\(secret)"]

        if let issuer = token.issuer, !issuer.isEmpty {
            queryItems.append("issuer=\(encodeValue(issuer))")
        }

        let algorithmString = switch token.algorithm {
        case .sha1: "SHA1"
        case .sha256: "SHA256"
        case .sha512: "SHA512"
        }
        queryItems.append("algorithm=\(algorithmString)")
        queryItems.append("digits=\(token.digits)")

        if token.type == .totp, let period = token.period {
            queryItems.append("period=\(period)")
        } else if token.type == .hotp, let counter = token.counter {
            queryItems.append("counter=\(counter)")
        }

        return "otpauth://\(typeStr)/\(label)?\(queryItems.joined(separator: "&"))"
    }
}
