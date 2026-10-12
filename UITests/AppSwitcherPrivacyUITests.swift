import CoreImage
import Vision
import XCTest

final class AppSwitcherPrivacyUITests: KeyaUITestCase {
    private func qrCodeCount(in screenshot: XCUIScreenshot) -> Int {
        guard let image = CIImage(image: screenshot.image),
              let detector = CIDetector(
                  ofType: CIDetectorTypeQRCode,
                  context: nil,
                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
              )
        else { return -1 }
        return detector.features(in: image).count
    }

    private func recognizedText(in screenshot: XCUIScreenshot) throws -> String {
        guard let cgImage = screenshot.image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    func testOpenQRExportIsCoveredInTheAppSwitcher() throws {
        try reachMainScreen()
        addToken(issuer: "Switcher", account: "switcher@example.com", secret: "JBSWY3DPEHPK3PXPJBSWY3DP")

        let row = element(labelContaining: "Switcher")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.swipeLeft()
        button(containing: "QR code").tap()
        if app.staticTexts["Enter PIN to unlock"].waitForExistence(timeout: 3) {
            enterPIN()
        }
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 5), app.debugDescription)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertGreaterThan(qrCodeCount(in: app.screenshot()), 0, "The QR code is on screen before leaving the app")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.999))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        bottom.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1.0)
        Thread.sleep(forTimeInterval: 3)

        let switcher = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: switcher)
        attachment.name = "app-switcher"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(qrCodeCount(in: switcher), 0, "No QR code may be visible in the app switcher")
        let text = try recognizedText(in: switcher).lowercased()
        XCTAssertFalse(text.contains("otpauth") || text.contains("secret="), "Secret text in the app switcher: \(text)")

        app.activate()
    }
}
