import Foundation
import SwiftUI

@Observable
final class EditTokenViewModel {
    // MARK: - Dependencies

    let tokenStore: TokenStore
    private let settings: AppSettings

    // MARK: - Published Properties

    var name: String
    var issuer: String
    var algorithm: Algorithm
    var digits: Int
    var period: String
    var counter: String
    var notes: String
    var isFavorite: Bool
    var groupName: String
    var website: String

    var errorMessage: String?
    var isSaving = false

    // MARK: - Duplicate confirmation

    struct PendingDuplicateAdd {
        let existingName: String
    }

    var pendingDuplicateAdd: PendingDuplicateAdd?

    // MARK: - Token Reference

    let originalToken: Token

    // MARK: - Initialization

    init(tokenStore: TokenStore, settings: AppSettings, token: Token) {
        self.tokenStore = tokenStore
        self.settings = settings
        originalToken = token

        name = token.name
        issuer = token.issuer ?? ""
        algorithm = token.algorithm
        digits = token.digits
        period = String(token.period ?? 30)
        counter = String(token.counter ?? 0)
        notes = token.notes ?? ""
        isFavorite = token.isFavorite
        groupName = token.groupName ?? ""
        website = token.website ?? ""
    }

    // MARK: - Save Token

    func saveToken() async -> Bool {
        guard validateInput() else { return false }

        var updatedToken = originalToken
        applyForm(to: &updatedToken)
        let duplicates = tokenStore.existingDuplicates(of: [updatedToken])
        if let duplicate = duplicates.first {
            pendingDuplicateAdd = PendingDuplicateAdd(existingName: duplicate.existing.name)
            return false
        }
        return persist()
    }

    func confirmPendingDuplicateSave() async -> Bool {
        guard pendingDuplicateAdd != nil else { return false }
        pendingDuplicateAdd = nil
        return persist()
    }

    func cancelPendingDuplicateSave() {
        pendingDuplicateAdd = nil
    }

    private func applyForm(to updatedToken: inout Token) {
        updatedToken.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedToken.issuer = issuer.isEmpty ? nil : issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedToken.algorithm = algorithm
        updatedToken.digits = digits
        updatedToken.notes = notes.isEmpty ? nil : notes
        updatedToken.isFavorite = isFavorite
        updatedToken.groupName = groupName.isEmpty ? nil : groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedToken.website = Token.websiteDomain(from: website)

        if originalToken.type == .totp {
            updatedToken.period = Int(period) ?? 30
        } else {
            updatedToken.counter = UInt64(counter) ?? 0
        }
    }

    private func persist() -> Bool {
        isSaving = true
        errorMessage = nil

        do {
            try tokenStore.update(id: originalToken.id) { applyForm(to: &$0) }

            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    // MARK: - Validation

    private func validateInput() -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "Name is required")
            return false
        }

        guard digits == 6 || digits == 8 else {
            errorMessage = String(localized: "Digits must be 6 or 8")
            return false
        }

        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedWebsite.isEmpty || Token.websiteDomain(from: trimmedWebsite) != nil else {
            errorMessage = String(localized: "Enter a website like example.com")
            return false
        }

        if originalToken.type == .totp {
            guard let periodValue = Int(period), periodValue >= 15, periodValue <= 300 else {
                errorMessage = String(localized: "Period must be between 15 and 300 seconds")
                return false
            }
        } else {
            guard UInt64(counter) != nil else {
                errorMessage = String(localized: "Counter must be a valid number")
                return false
            }
        }

        return true
    }

    // MARK: - Token Type Display

    var tokenTypeDisplayName: String {
        originalToken.type.displayName
    }

    // MARK: - Secret Display

    var secretDisplay: String {
        originalToken.secret.base32EncodedString
    }
}
