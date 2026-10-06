import XCTest
@testable import Keya_Authenticator

final class LocalizationTests: XCTestCase {
    private func localized(_ value: String.LocalizationValue, _ language: String) -> String {
        var resource = LocalizedStringResource(value)
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }

    func testErrorMessagesAreTranslated() {
        XCTAssertEqual(localized("Incorrect PIN", "fr"), "Code PIN incorrect")
        XCTAssertEqual(localized("Your tokens couldn't be deleted. Please try again.", "es-419"),
                       "No se pudieron eliminar tus tokens. Inténtalo de nuevo.")
        XCTAssertEqual(localized("No camera available", "ja"), "利用できるカメラがありません")
    }

    func testSkippedImportUsesPluralForms() {
        let one = localized(
            "\(1) tokens could not be imported because the data was missing or invalid. The remaining tokens were imported successfully.",
            "fr"
        )
        let many = localized(
            "\(3) tokens could not be imported because the data was missing or invalid. The remaining tokens were imported successfully.",
            "fr"
        )
        XCTAssertTrue(one.hasPrefix("1 jeton n'a pas pu"), one)
        XCTAssertTrue(many.hasPrefix("3 jetons n'ont pas pu"), many)
        XCTAssertEqual(localized("\(1) tokens could not be imported because the data was missing or invalid. The remaining tokens were imported successfully.", "en"),
                       "1 token could not be imported because the data was missing or invalid.\nThe remaining tokens were imported successfully.")
    }

    func testAlreadyInVaultUsesPluralForms() {
        XCTAssertEqual(localized("\(1) tokens are already in your vault and were kept as they are.", "en"),
                       "1 token is already in your vault and was kept as it is.")
        XCTAssertEqual(localized("\(3) tokens are already in your vault and were kept as they are.", "fr"),
                       "3 jetons sont déjà dans votre coffre et ont été conservés tels quels.")
        XCTAssertEqual(localized("\(1) tokens are already in your vault and were kept as they are.", "pt-BR"),
                       "1 token já está no seu cofre e foi mantido como estava.")
    }

    func testAsianLanguagesHaveNoEnglishPluralSuffix() {
        let ja = localized(
            "\(2) tokens could not be imported because the data was missing or invalid. The remaining tokens were imported successfully.",
            "ja"
        )
        let ko = localized(
            "\(2) tokens could not be imported because the data was missing or invalid. The remaining tokens were imported successfully.",
            "ko"
        )
        XCTAssertFalse(ja.contains("s"), ja)
        XCTAssertTrue(ja.contains("2個のトークン"), ja)
        XCTAssertTrue(ko.contains("2개의 토큰"), ko)
    }

    func testInterpolatedMessagesKeepArgumentOrder() {
        XCTAssertEqual(localized("\("Keya") doesn't have permission to use \("Face ID"). Tap 'Open Settings' to allow it.", "fr"),
                       "Keya n'a pas l'autorisation d'utiliser Face ID. Touchez « Ouvrir les Réglages » pour l'autoriser.")
    }
}
