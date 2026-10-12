import XCTest
@testable import Keya_Authenticator

final class BiometricBaselineTests: XCTestCase {
    private let stored = Data([1, 2, 3])

    func testNoBaselineMeansNoChange() {
        XCTAssertFalse(BiometricBaseline.hasChanged(stored: nil, current: Data([9])))
        XCTAssertFalse(BiometricBaseline.hasChanged(stored: nil, current: nil))
    }

    func testSameStateIsNoChange() {
        XCTAssertFalse(BiometricBaseline.hasChanged(stored: stored, current: stored))
    }

    func testDifferentStateIsAChange() {
        XCTAssertTrue(BiometricBaseline.hasChanged(stored: stored, current: Data([4])))
    }

    func testUnreadableStateIsAChange() {
        XCTAssertTrue(BiometricBaseline.hasChanged(stored: stored, current: nil))
    }
}
