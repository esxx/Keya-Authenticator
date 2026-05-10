import AVFoundation
import Foundation
import PhotosUI
import SwiftUI

@Observable
final class AddTokenViewModel {
    // MARK: - Dependencies

    let tokenStore: TokenStore
    private let settings: AppSettings
    let importManager: ExportImportManager

    // MARK: - Manual-entry form state

    var name = ""
    var issuer = ""
    var secret = ""
    var algorithm: Algorithm = .sha1
    var digits: Int = 6
    var period: Int = 30
    var counter: UInt64 = 0
    var tokenType: TokenType = .totp
    var groupName: String?
    var isFavorite = false
    var isAddingToken = false

    // MARK: - Import state (file / gallery / encrypted)

    var isImporting = false
    var pendingEncryptedData: Data?
    var showEncryptedImportSheet = false
    var importSkippedCount = 0

    // MARK: - Shared error + dismiss signal

    var errorMessage: String?
    var shouldDismiss = false

    // MARK: - Callback (set by the presenting view before the sheet appears)

    var onTokenAdded: (() -> Void)?

    // MARK: - Initialization

    init(tokenStore: TokenStore, settings: AppSettings) {
        self.tokenStore = tokenStore
        self.settings = settings
        importManager = ExportImportManager(tokenStore: tokenStore)
    }

    // MARK: - Token Creation (manual form)

    func createToken() {
        guard validateInput() else { return }
        isAddingToken = true
        do {
            let token = try buildToken()
            var current = tokenStore.tokens
            current.append(token)
            try tokenStore.update(current)
            resetForm()
            ClipboardManager.shared.provideHapticFeedback(.success)
            onTokenAdded?()
            shouldDismiss = true
        } catch {
            ClipboardManager.shared.provideHapticFeedback(.error)
            errorMessage = "Failed to create token: \(error.localizedDescription)"
        }
        isAddingToken = false
    }

    private func buildToken() throws -> Token {
        guard let secretData = secret.base32DecodedData else {
            throw NSError(
                domain: "TokenError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid secret"]
            )
        }
        return Token(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            issuer: issuer.isEmpty ? nil : issuer.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: secretData,
            algorithm: algorithm,
            digits: digits,
            type: tokenType,
            period: period,
            counter: counter,
            isFavorite: isFavorite,
            groupName: groupName?.isEmpty == true ? nil : groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func validateInput() -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "Name is required")
            return false
        }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "Secret is required")
            return false
        }
        guard let secretData = secret.base32DecodedData else {
            errorMessage = String(localized: "Invalid Base32 secret. Check the key and try again.")
            return false
        }
        guard secretData.count >= 10 else {
            errorMessage = String(localized: "Secret must be at least 10 bytes for security")
            return false
        }
        guard digits == 6 || digits == 8 else {
            errorMessage = String(localized: "Digits must be 6 or 8")
            return false
        }
        guard tokenType == .hotp || (period >= 15 && period <= 300) else {
            errorMessage = String(localized: "Period must be between 15 and 300 seconds")
            return false
        }
        return true
    }

    // MARK: - QR — live scanner (AddTokenView: persists immediately)

    func handleScannedQR(_ string: String) {
        errorMessage = nil
        if string.hasPrefix("otpauth-migration://") {
            guard let params = string.parseMigrationURI() else {
                errorMessage = String(localized: "Could not decode Google Authenticator QR code")
                return
            }
            let validParams = params.filter { $0.secret.count >= 10 }
            guard !validParams.isEmpty else {
                errorMessage = String(localized: "No valid tokens found in QR code")
                return
            }
            let skipped = params.count - validParams.count
            if skipped > 0 {
                importSkippedCount = skipped
            }
            let tokens = validParams.map {
                Token(
                    name: $0.name,
                    issuer: $0.issuer,
                    secret: $0.secret,
                    algorithm: $0.algorithm,
                    digits: $0.digits,
                    type: $0.type,
                    period: $0.period,
                    counter: $0.counter
                )
            }
            persistImported(tokens)
        } else if let p = string.extractOTPParameters() {
            guard let secretData = p.secret.base32DecodedData, secretData.count >= 10 else {
                errorMessage = String(localized: "Invalid Base32 secret. Check the key and try again.")
                return
            }
            persistImported([Token(
                name: p.name.isEmpty ? "Imported Token" : p.name,
                issuer: p.issuer?.isEmpty == true ? nil : p.issuer,
                secret: secretData, algorithm: p.algorithm, digits: p.digits, type: p.type,
                period: p.type == .totp ? (p.period ?? 30) : nil,
                counter: p.type == .hotp ? (p.counter ?? 0) : nil
            )])
        } else {
            errorMessage = String(localized: "Invalid QR code")
        }
    }

    // MARK: - QR — manual form (ManualTokenEntryView: populates form fields)

    func processQRScanResult(_ result: Result<String, Error>) {
        switch result {
        case let .success(qr):
            errorMessage = nil
            if qr.hasPrefix("otpauth-migration://") {
                guard let params = qr.parseMigrationURI() else {
                    errorMessage = String(localized: "Could not decode Google Authenticator QR code")
                    return
                }
                let validParams = params.filter { $0.secret.count >= 10 }
                guard !validParams.isEmpty else {
                    errorMessage = String(localized: "No valid tokens found in QR code")
                    return
                }
                let skipped = params.count - validParams.count
                if skipped > 0 { importSkippedCount = skipped }
                let tokens = validParams.map {
                    Token(
                        name: $0.name,
                        issuer: $0.issuer,
                        secret: $0.secret,
                        algorithm: $0.algorithm,
                        digits: $0.digits,
                        type: $0.type,
                        period: $0.period,
                        counter: $0.counter
                    )
                }
                persistImported(tokens)
            } else if let params = qr.extractOTPParameters() {
                // Populate form for review
                name = params.name
                issuer = params.issuer ?? ""
                secret = params.secret
                tokenType = params.type
                algorithm = params.algorithm
                // Clamp digits to the only two valid values (6 or 8); silently default
                // to 6 for anything else rather than accepting an arbitrary Int.
                digits = (params.digits == 8) ? 8 : 6
                // Clamp period to a sane range. URIs occasionally carry out-of-spec
                // values; silently coercing them to 30 would hide the issue, so we
                // explicitly validate and fall back to the standard 30 s default.
                if let p = params.period {
                    period = (p >= 15 && p <= 300) ? p : 30
                }
                if let c = params.counter { counter = c }
            } else {
                secret = qr
            }
        case let .failure(err):
            errorMessage = err.localizedDescription
        }
    }

    // MARK: - Gallery photo (AddTokenView: persist result)

    func importGalleryPhoto(_ item: PhotosPickerItem) async {
        switch await extractQRFromPhoto(item) {
        case let .success(qr):
            await MainActor.run { handleScannedQR(qr) }
        case let .failure(err):
            await MainActor.run { errorMessage = err.localizedDescription }
        }
    }

    // MARK: - Gallery photo (ManualTokenEntryView: populate form)

    func loadGalleryPhotoIntoForm(_ item: PhotosPickerItem) async {
        switch await extractQRFromPhoto(item) {
        case let .success(qr):
            await MainActor.run { processQRScanResult(.success(qr)) }
        case let .failure(err):
            await MainActor.run { errorMessage = err.localizedDescription }
        }
    }

    // MARK: - File import

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            Task {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                // Read the file exactly once to avoid TOCTOU issues
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    await MainActor.run { errorMessage = String(localized: "Could not read the file") }
                    return
                }
                let importResult: ExportImportManager.ImportResult
                do {
                    importResult = try importManager.parseTokens(from: data)
                } catch ExportImportError.encryptedFileRequiresPassword {
                    await MainActor.run {
                        pendingEncryptedData = data
                        showEncryptedImportSheet = true
                    }
                    return
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                    return
                }
                await MainActor.run {
                    importSkippedCount = importResult.skipped
                    persistImported(importResult.tokens)
                }
            }
        case let .failure(err):
            errorMessage = err.localizedDescription
        }
    }

    func handleEncryptedImportResult(_ result: ExportImportManager.ImportResult?) {
        pendingEncryptedData = nil
        showEncryptedImportSheet = false
        guard let result else { return }
        importSkippedCount = result.skipped
        do {
            var current = tokenStore.tokens
            current.append(contentsOf: result.tokens)
            try tokenStore.update(current)
            onTokenAdded?()
            shouldDismiss = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Form Management

    func resetForm() {
        name = ""
        issuer = ""
        secret = ""
        algorithm = .sha1
        digits = 6
        period = 30
        counter = 0
        tokenType = .totp
        groupName = nil
        isFavorite = false
        errorMessage = nil
    }

    // MARK: - Camera Permission

    func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: fallthrough
        @unknown default: return false
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        resetForm()
    }

    // MARK: - Private helpers

    private func persistImported(_ tokens: [Token]) {
        isImporting = true
        do {
            var current = tokenStore.tokens
            current.append(contentsOf: tokens)
            try tokenStore.update(current)
            ClipboardManager.shared.provideHapticFeedback(.success)
            onTokenAdded?()
            shouldDismiss = true
        } catch {
            ClipboardManager.shared.provideHapticFeedback(.error)
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }

    private func extractQRFromPhoto(_ item: PhotosPickerItem) async -> Result<String, Error> {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let ciImage = CIImage(image: uiImage)
        else {
            return .failure(NSError(
                domain: "Gallery",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not load the selected photo."]
            ))
        }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        guard let qr = (detector?.features(in: ciImage) as? [CIQRCodeFeature])?.first?.messageString else {
            return .failure(NSError(
                domain: "Gallery",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No QR code found in the selected photo."]
            ))
        }
        return .success(qr)
    }
}
