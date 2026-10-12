import UIKit
import XCTest
@testable import Keya_Authenticator

@MainActor
final class KeyboardPolicyTests: XCTestCase {
    func testThirdPartyKeyboardsAreNotAllowed() throws {
        let delegate = try XCTUnwrap(UIApplication.shared.delegate)
        let allowed = delegate.application?(UIApplication.shared, shouldAllowExtensionPointIdentifier: .keyboard)
        XCTAssertEqual(allowed, false)
    }
}
