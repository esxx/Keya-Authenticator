import XCTest
@testable import Keya_Authenticator

@MainActor
final class ClipboardManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UIPasteboard.general.items = []
    }

    override func tearDown() {
        UIPasteboard.general.items = []
        super.tearDown()
    }

    func testCopyPutsTextOnPasteboard() {
        ClipboardManager.shared.copyToClipboard("123456", autoClearDelay: nil)
        XCTAssertEqual(UIPasteboard.general.string, "123456")
    }

    func testCopyWithExpiryStillPutsTextOnPasteboardImmediately() {
        ClipboardManager.shared.copyToClipboard("654321", autoClearDelay: 30)
        XCTAssertEqual(UIPasteboard.general.string, "654321")
    }

    func testClearEmptiesPasteboard() {
        ClipboardManager.shared.copyToClipboard("123456", autoClearDelay: nil)
        XCTAssertFalse(UIPasteboard.general.items.isEmpty)
        ClipboardManager.shared.clearClipboard()
        XCTAssertTrue(UIPasteboard.general.items.isEmpty)
    }

    func testSecondCopyOverwritesFirst() {
        ClipboardManager.shared.copyToClipboard("111111", autoClearDelay: nil)
        ClipboardManager.shared.copyToClipboard("999999", autoClearDelay: nil)
        XCTAssertEqual(UIPasteboard.general.string, "999999")
    }
}
