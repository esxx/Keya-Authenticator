import Foundation
import SwiftUI

@Observable
final class QRExportViewModel {
    // MARK: - Published Properties

    var qrImage: UIImage?
    var otpauthURI: String = ""

    // MARK: - Token Reference

    private let token: Token

    // MARK: - Initialization

    init(token: Token) {
        self.token = token
        generateQR()
    }

    // MARK: - QR Generation

    private func generateQR() {
        otpauthURI = QRCodeGenerator.generateOTPAuthURI(from: token)
        qrImage = QRCodeGenerator.generateQRCode(from: otpauthURI)
    }

    // MARK: - Token Info

    var tokenName: String {
        token.name
    }

    var tokenIssuer: String? {
        token.issuer
    }

    var displayName: String {
        token.displayName
    }
}
