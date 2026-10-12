import XCTest

final class AddSheetLayoutUITests: KeyaUITestCase {
    func testScannerLeavesRoomForEveryOtherMethod() throws {
        try reachMainScreen()
        app.buttons["Add"].tap()
        dismissSystemAlertIfPresent()

        let scanner = app.otherElements["qrScanner"]
        XCTAssertTrue(scanner.waitForExistence(timeout: 5), app.debugDescription)
        let preview = scanner.otherElements.element(boundBy: 0).frame
        XCTAssertLessThanOrEqual(preview.height, preview.width + 1, "\(preview)")

        let lastRow = button(containing: "Enter the secret key manually")
        XCTAssertTrue(lastRow.waitForExistence(timeout: 5), app.debugDescription)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(lastRow.frame.maxY, window.maxY - 34, "\(lastRow.frame) in \(window)")
    }
}
