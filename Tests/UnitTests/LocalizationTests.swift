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

    func testBackupPasswordLengthMessageIsTranslated() {
        XCTAssertEqual(localized("Password must be at least 8 characters.", "es-419"),
                       "La contraseña debe tener al menos 8 caracteres.")
        XCTAssertEqual(localized("Password must be at least 8 characters.", "fr"),
                       "Le mot de passe doit contenir au moins 8 caractères.")
        XCTAssertEqual(localized("Password must be at least 8 characters.", "ja"), "パスワードは8文字以上にしてください。")
        XCTAssertEqual(localized("Password must be at least 8 characters.", "ko"), "비밀번호는 8자 이상이어야 합니다.")
        XCTAssertEqual(localized("Password must be at least 8 characters.", "pt-BR"),
                       "A senha deve ter pelo menos 8 caracteres.")
    }

    func testImportedTokenFallbackNameIsTranslated() {
        XCTAssertEqual(localized("Imported Token", "es-419"), "Token importado")
        XCTAssertEqual(localized("Imported Token", "fr"), "Jeton importé")
        XCTAssertEqual(localized("Imported Token", "ja"), "インポートしたトークン")
        XCTAssertEqual(localized("Imported Token", "ko"), "가져온 토큰")
        XCTAssertEqual(localized("Imported Token", "pt-BR"), "Token importado")
    }

    func testPermissionPromptsAreTranslated() throws {
        let keys = ["NSCameraUsageDescription", "NSFaceIDUsageDescription", "NSPhotoLibraryUsageDescription"]
        for language in ["es-419", "fr", "ja", "ko", "pt-BR", "ru", "de", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path), language)
            for key in keys {
                let english = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? String, key)
                let value = bundle.localizedString(forKey: key, value: nil, table: "InfoPlist")
                XCTAssertNotEqual(value, key, "\(language) \(key)")
                XCTAssertNotEqual(value, english, "\(language) \(key)")
            }
        }
        let fr = try XCTUnwrap(Bundle.main.path(forResource: "fr", ofType: "lproj").flatMap(Bundle.init(path:)))
        XCTAssertEqual(fr.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist"),
                       "L'accès à la caméra est nécessaire pour scanner les QR codes lors de l'ajout de comptes 2FA.")
    }

    private func tableKeys(_ name: String, _ type: String, _ language: String) throws -> Set<String> {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: name, ofType: type, inDirectory: nil, forLocalization: language),
            "\(language) \(name).\(type)"
        )
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: Any], path)
        return Set(table.keys)
    }

    func testNewLanguagesCoverEveryTranslatedString() throws {
        let strings = try tableKeys("Localizable", "strings", "fr")
        let plurals = try tableKeys("Localizable", "stringsdict", "fr")
        for language in ["ru", "de", "zh-Hans"] {
            XCTAssertEqual(try tableKeys("Localizable", "strings", language).symmetricDifference(strings), [], language)
            XCTAssertEqual(try tableKeys("Localizable", "stringsdict", language).symmetricDifference(plurals), [], language)
        }
    }

    func testNewLanguagesReadNaturally() {
        XCTAssertEqual(localized("Incorrect PIN", "ru"), "Неверный PIN-код")
        XCTAssertEqual(localized("Incorrect PIN", "de"), "Falsche PIN")
        XCTAssertEqual(localized("Incorrect PIN", "zh-Hans"), "PIN 码错误")
        XCTAssertEqual(localized("Imported Token", "ru"), "Импортированный токен")
        XCTAssertEqual(localized("Imported Token", "de"), "Importierter Token")
        XCTAssertEqual(localized("Imported Token", "zh-Hans"), "导入的令牌")
    }

    func testSharedLabelsFitEveryPlaceTheyAppear() {
        let confirm = ["es-419": "Confirmar", "fr": "Confirmer", "ja": "確認", "ko": "확인", "pt-BR": "Confirmar"]
        let copied = ["es-419": "Copiado", "fr": "Copié", "ja": "コピーしました", "ko": "복사됨", "pt-BR": "Copiado"]
        for (language, expected) in confirm {
            XCTAssertEqual(localized("Confirm", language), expected, language)
        }
        for (language, expected) in copied {
            XCTAssertEqual(localized("Copied", language), expected, language)
        }
        XCTAssertEqual(localized("Favorite", "es-419"), "Favorito")
        XCTAssertEqual(localized("Favorite", "ja"), "お気に入り")
    }

    func testLockoutWarningStartsSecondSentenceOnNewLine() {
        for language in ["en", "es-419", "fr", "ja", "ko", "pt-BR", "ru", "de", "zh-Hans"] {
            let warnings = [
                localized("Incorrect PIN. One more wrong PIN locks entry for \(30) seconds.", language),
                localized("Incorrect PIN. One more wrong PIN locks entry for \(5) minutes.", language),
            ]
            for warning in warnings {
                let lines = warning.components(separatedBy: "\n")
                XCTAssertEqual(lines.count, 2, "\(language): \(warning)")
                XCTAssertTrue(lines.first?.hasSuffix(".") == true || lines.first?.hasSuffix("。") == true,
                              "\(language): \(warning)")
            }
        }
        XCTAssertEqual(localized("Incorrect PIN. One more wrong PIN locks entry for \(30) seconds.", "ru"),
                       "Неверный PIN-код.\nЕщё одна ошибка, и вход заблокируется на 30 секунд.")
    }

    func testChineseUsesSystemBiometricNames() {
        XCTAssertEqual(localized("Face ID", "zh-Hans"), "面容 ID")
        XCTAssertEqual(localized("Touch ID", "zh-Hans"), "触控 ID")
        XCTAssertEqual(localized("Face ID", "de"), "Face ID")
        XCTAssertEqual(localized("Touch ID", "ru"), "Touch ID")
        let changed = localized(
            "The Face ID / Touch ID database on this device has changed since your last login. Biometric unlock has been disabled as a security precaution. You can re-enable it in Settings → App lock once you've confirmed the change was made by you.",
            "zh-Hans"
        )
        XCTAssertTrue(changed.contains("设备上的面容 ID / 触控 ID 数据"), changed)
        XCTAssertEqual(localized("Unlock with \("面容 ID")", "zh-Hans"), "使用面容 ID 解锁")
        XCTAssertEqual(localized("Confirm to enable \("面容 ID") unlock", "zh-Hans"), "确认以启用面容 ID 解锁")
    }

    func testGermanAddressesTheUserFormally() throws {
        let informal = try NSRegularExpression(pattern: #"\b(du|dein\w*|dich|dir)\b"#, options: [.caseInsensitive])
        for table in ["Localizable", "InfoPlist"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: "de"))
            let strings = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], path)
            for value in strings.values {
                let range = NSRange(value.startIndex..., in: value)
                XCTAssertNil(informal.firstMatch(in: value, range: range), "\(table): \(value)")
            }
        }
        XCTAssertEqual(localized("Enter PIN to unlock", "de"), "Geben Sie zum Entsperren Ihre PIN ein")
        XCTAssertEqual(localized("Back up your tokens", "de"), "Sichern Sie Ihre Tokens")
        XCTAssertEqual(localized("Tap to reveal your authentication code", "de"), "Tippen Sie, um Ihren Code anzuzeigen")
    }

    func testFrenchDeleteConfirmationNamesTheToken() {
        XCTAssertEqual(localized("This will permanently delete \("GitHub"). This cannot be undone.", "fr"),
                       "Cela supprimera définitivement « GitHub ». Cette action est irréversible.")
    }

    func testJapaneseAndKoreanUseOnlyTheOtherPluralForm() throws {
        for language in ["ja", "ko"] {
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: "Localizable", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            )
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: [String: Any]], path)
            let entry = try XCTUnwrap(table["%lld seconds left"], language)
            for case let rule as [String: Any] in entry.values {
                XCTAssertNil(rule["one"], "\(language): \(rule)")
            }
        }
    }

    func testRussianUsesThreePluralForms() {
        let message: (Int) -> String = {
            self.localized("\($0) tokens are already in your vault and were kept as they are.", "ru")
        }
        XCTAssertEqual(message(1), "1 токен уже есть в хранилище, его оставили без изменений.")
        XCTAssertEqual(message(3), "3 токена уже есть в хранилище, их оставили без изменений.")
        XCTAssertEqual(message(5), "5 токенов уже есть в хранилище, их оставили без изменений.")
        XCTAssertEqual(message(21), "21 токен уже есть в хранилище, его оставили без изменений.")
    }

    func testInterpolatedMessagesKeepArgumentOrder() {
        XCTAssertEqual(localized("\("Keya") doesn't have permission to use \("Face ID"). Tap 'Open Settings' to allow it.", "fr"),
                       "Keya n'a pas l'autorisation d'utiliser Face ID. Touchez « Ouvrir les Réglages » pour l'autoriser.")
    }

    func testSystemNamesMatchApple() throws {
        let nonAppleTerms = [
            "es-419": #"(?i)\bajustes?\b"#,
            "pt-BR": #"(?i)configuraç|keychain"#,
            "fr": #"(?i)\bparamètres?\b"#,
            "ja": "フォトライブラリ",
        ]
        for (language, pattern) in nonAppleTerms {
            let regex = try NSRegularExpression(pattern: pattern)
            for table in ["Localizable", "InfoPlist"] {
                let path = try XCTUnwrap(
                    Bundle.main.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: language)
                )
                let strings = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], path)
                for value in strings.values {
                    let range = NSRange(value.startIndex..., in: value)
                    XCTAssertNil(regex.firstMatch(in: value, range: range), "\(language) \(table): \(value)")
                }
            }
        }
        XCTAssertEqual(localized("Settings", "es-419"), "Configuración")
        XCTAssertEqual(localized("Settings", "pt-BR"), "Ajustes")
        XCTAssertEqual(localized("Open Settings", "pt-BR"), "Abrir Ajustes")
        XCTAssertEqual(localized("Notes are stored securely in the iOS Keychain", "pt-BR"),
                       "As notas são armazenadas com segurança nas Chaves do iOS")
        XCTAssertEqual(localized("Import from Photo Library", "ja"), "写真ライブラリからインポート")
    }

    func testJapaneseAndRussianQuoteMenuNames() throws {
        let unquotedStep = [
            "ja": #"[^」\s]\s*→|→\s*[^\s「]"#,
            "ru": #"[^»\s]\s*→|→\s*[^\s«]"#,
        ]
        for (language, pattern) in unquotedStep {
            let regex = try NSRegularExpression(pattern: pattern)
            let path = try XCTUnwrap(
                Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            )
            let strings = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], path)
            for value in strings.values where value.contains("→") {
                let range = NSRange(value.startIndex..., in: value)
                XCTAssertNil(regex.firstMatch(in: value, range: range), "\(language): \(value)")
            }
        }
        XCTAssertEqual(localized("Camera access is required to scan QR codes. Enable it in Settings.", "ja"),
                       "QRコードをスキャンするにはカメラへのアクセスが必要です。「設定」で許可してください。")
        XCTAssertEqual(localized("Camera access is required to scan QR codes. Enable it in Settings.", "ru"),
                       "Чтобы сканировать QR-коды, нужен доступ к камере. Разрешите его в «Настройках».")
        XCTAssertEqual(localized("Import from Files", "ja"), "「ファイル」からインポート")
        XCTAssertEqual(localized("Import from Files", "ru"), "Импорт из «Файлов»")
    }
}
