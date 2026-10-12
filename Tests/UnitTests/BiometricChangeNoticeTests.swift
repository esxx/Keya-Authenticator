import XCTest
@testable import Keya_Authenticator

final class BiometricChangeNoticeTests: XCTestCase {
    func testReadableButDifferentDataKeepsTheChangeMessage() {
        let notice = BiometricChangeNotice(biometricsAvailable: true)
        XCTAssertEqual(notice, .changed)
        XCTAssertEqual(notice.title, String(localized: "Biometric database changed"))
    }

    func testUnavailableBiometricsPointToIOSSettingsFirst() {
        let notice = BiometricChangeNotice(biometricsAvailable: false)
        XCTAssertEqual(notice, .unavailable)
        XCTAssertEqual(notice.title, "Biometric unlock turned off")
        XCTAssertTrue(notice.message.hasPrefix("Biometric unlock has been turned off, so Keya can't use"), notice.message)
        XCTAssertTrue(notice.message.contains("iOS Settings → Face ID & Passcode → Other Apps"), notice.message)
        XCTAssertTrue(notice.message.contains("Keya's Settings → App lock"), notice.message)
        XCTAssertFalse(notice.message.contains("database"), notice.message)
    }
}
