import XCTest
@testable import Keya_Authenticator

final class TokenRowAccessibilityTests: XCTestCase {
    func testVisibleTOTPCodeIsSpelledOutWithSecondsLeft() {
        XCTAssertEqual(
            TokenRowView.accessibilityCodeValue(code: "123456", isVisible: true, secondsLeft: 12),
            "1 2 3 4 5 6, 12 seconds left"
        )
        XCTAssertEqual(
            TokenRowView.accessibilityCodeValue(code: "12345678", isVisible: true, secondsLeft: 1),
            "1 2 3 4 5 6 7 8, 1 second left"
        )
    }

    func testHOTPCodeHasNoCountdown() {
        XCTAssertEqual(TokenRowView.accessibilityCodeValue(code: "654321", isVisible: true, secondsLeft: nil), "6 5 4 3 2 1")
    }

    func testHiddenCodeIsNeverSpoken() {
        XCTAssertEqual(TokenRowView.accessibilityCodeValue(code: "123456", isVisible: false, secondsLeft: 12), "Code hidden")
    }

    func testMissingCodeHasNoValue() {
        XCTAssertEqual(TokenRowView.accessibilityCodeValue(code: nil, isVisible: true, secondsLeft: 12), "")
    }

    func testSecondsLeftLabelIsShortAndLocalized() {
        XCTAssertEqual(TokenRowView.secondsLeftLabel(12, locale: Locale(identifier: "en_US")), "12s")
        XCTAssertNotEqual(TokenRowView.secondsLeftLabel(12, locale: Locale(identifier: "ru_RU")), "12s",
                          "The unit follows the language")
    }
}
