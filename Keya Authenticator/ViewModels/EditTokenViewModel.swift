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

    var errorMessage: String?
    var isSaving = false

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
    }

    // MARK: - Save Token

    func saveToken() async -> Bool {
        guard validateInput() else { return false }

        isSaving = true
        errorMessage = nil

        do {
            var updatedToken = originalToken
            updatedToken.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedToken.issuer = issuer.isEmpty ? nil : issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedToken.algorithm = algorithm
            updatedToken.digits = digits
            updatedToken.notes = notes.isEmpty ? nil : notes
            updatedToken.isFavorite = isFavorite
            updatedToken.groupName = groupName.isEmpty ? nil : groupName.trimmingCharacters(in: .whitespacesAndNewlines)

            if originalToken.type == .totp {
                updatedToken.period = Int(period) ?? 30
            } else {
                updatedToken.counter = UInt64(counter) ?? 0
            }

            updatedToken.touch()

            var tokens = tokenStore.tokens
            guard let idx = tokens.firstIndex(where: { $0.id == originalToken.id }) else {
                errorMessage = String(localized: "Token not found")
                isSaving = false
                return false
            }

            tokens[idx] = updatedToken
            try tokenStore.update(tokens)

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
