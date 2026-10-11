import Foundation

enum ReviewPrompt {
    static let minimumActiveDays = 5
    static let minimumTokens = 2

    static func shouldRequest(
        activeDays: Int,
        tokenCount: Int,
        currentVersion: String,
        lastPromptedVersion: String?
    ) -> Bool {
        activeDays >= minimumActiveDays && tokenCount >= minimumTokens && currentVersion != lastPromptedVersion
    }
}
