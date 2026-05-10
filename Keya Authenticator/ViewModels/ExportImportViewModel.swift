import Foundation
import SwiftUI

@Observable
final class ExportImportViewModel {
    // MARK: - Dependencies

    let tokenStore: TokenStore
    let exportImportManager: ExportImportManager
    let settings: AppSettings

    // MARK: - Published Properties

    var isExporting = false
    var exportError: String?
    var exportData: Data?
    var showExportPicker = false
    var showMigrationQR = false
    var showExportSuccess = false
    var exportFilename = ""

    var showEncryptedExportSheet = false

    var hasTokens: Bool {
        !tokenStore.tokens.isEmpty
    }

    // MARK: - Initialization

    init(tokenStore: TokenStore, settings: AppSettings) {
        self.tokenStore = tokenStore
        self.settings = settings
        exportImportManager = ExportImportManager(tokenStore: tokenStore)
    }

    // MARK: - Export Functions

    func startJSONExport() {
        isExporting = true
        exportError = nil

        Task { @MainActor in
            do {
                let data = try exportImportManager.exportVault()
                exportData = data
                isExporting = false
                showExportPicker = true
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            exportData = nil
            settings.lastBackupDate = Date()
            showExportSuccess = true
        case let .failure(error):
            exportError = error.localizedDescription
        }
    }

    // MARK: - Filename Generation

    var defaultExportFilename: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "keya-authenticator-backup-\(df.string(from: Date())).json"
    }

    var defaultEncryptedExportFilename: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "keya-authenticator-backup-encrypted-\(df.string(from: Date())).json"
    }

    // MARK: - Cleanup

    func cleanup() {
        exportData = nil
        exportError = nil
    }
}
