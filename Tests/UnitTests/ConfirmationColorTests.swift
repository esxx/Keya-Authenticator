import SwiftUI
import XCTest
@testable import Keya_Authenticator

final class ConfirmationColorTests: XCTestCase {
    func testWhiteTextOnTheConfirmationGreenMeetsHIGContrast() {
        XCTAssertGreaterThanOrEqual(ContrastMath.ratio(.white, over: Constants.Colors.confirmationGreen), 4.5,
                                    "The New badge and the Copied toast use white text on this green")
    }
}
