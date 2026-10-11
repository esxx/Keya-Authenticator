import XCTest
@testable import Keya_Authenticator

@MainActor
final class ExportImportViewModelTests: XCTestCase {
    func testExportFailureIsAnnounced() {
        let viewModel = ExportImportViewModel(tokenStore: TokenStore(), settings: AppSettings())
        var spoken: [String] = []
        viewModel.announce = { spoken.append($0) }
        let failure = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])

        viewModel.handleExportResult(.failure(failure))

        XCTAssertEqual(viewModel.exportError, "Disk full")
        XCTAssertEqual(spoken, ["Disk full"])
    }
}
