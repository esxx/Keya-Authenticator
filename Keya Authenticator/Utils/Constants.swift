import Foundation
import SwiftUI

enum Constants {
    // MARK: - App Info

    static let appName = String(localized: "app.name")
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // MARK: - Keychain

    static let keychainService = "ee.exx.KeyaAuthenticator"

    // MARK: - URLs

    static let aboutURL = URL(string: "https://esxx.github.io/Keya-Authenticator/")
    static let privacyPolicyURL = URL(string: "https://esxx.github.io/Keya-Authenticator/privacy.html")
    static let termsOfServiceURL = URL(string: "https://esxx.github.io/Keya-Authenticator/terms.html")
    static let faqURL = URL(string: "https://esxx.github.io/Keya-Authenticator/faq.html")
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6764358712?action=write-review")

    // MARK: - Colors

    enum Colors {
        static let background = Color(uiColor: .systemGroupedBackground)
        static let rowBackground = Color(uiColor: .secondarySystemGroupedBackground)
        static let confirmationGreen = Color(red: 35 / 255, green: 136 / 255, blue: 61 / 255)
    }
}
