import Foundation
import SwiftUI

@Observable
final class MainContentViewModel {
    // MARK: - Dependencies

    let tokenStore: TokenStore
    let authenticationManager: AuthenticationManager
    let settings: AppSettings

    // MARK: - Published Properties

    var searchText = ""
    var showingAddSheet = false
    var showingSettings = false
    var selectedTokenForEdit: Token?
    var selectedTokenForQR: Token?
    var showCopyToast = false
    var tokenPendingDelete: Token?
    var showBackupNudge = false
    var showExportSheet = false

    // MARK: - Private State

    private var newTokenIDs: Set<UUID> = []
    private var snapshotIDsBeforeAdd: Set<UUID> = []
    private var hotpIncrementInProgress = false

    // MARK: - Computed Properties

    var filteredTokens: [Token] {
        if searchText.isEmpty { return tokenStore.tokens }
        let query = searchText.lowercased()
        return tokenStore.tokens.filter {
            $0.name.lowercased().contains(query) ||
                ($0.issuer?.lowercased().contains(query) ?? false) ||
                ($0.groupName?.lowercased().contains(query) ?? false)
        }
    }

    var favoriteTokens: [Token] {
        filteredTokens.filter(\.isFavorite)
    }

    var groupedOtherTokens: [TokenGroup] {
        let others = filteredTokens.filter { !$0.isFavorite }
        var byName: [String: [Token]] = [:]
        var ungrouped: [Token] = []
        for token in others {
            if let g = token.groupName, !g.isEmpty {
                byName[g, default: []].append(token)
            } else {
                ungrouped.append(token)
            }
        }
        var result: [TokenGroup] = byName.keys.sorted().map { name in
            TokenGroup(id: name, title: name, tokens: byName[name] ?? [])
        }
        if !ungrouped.isEmpty {
            result.append(TokenGroup(id: "", title: nil, tokens: ungrouped))
        }
        return result
    }

    // MARK: - Initialization

    init(tokenStore: TokenStore, authenticationManager: AuthenticationManager, settings: AppSettings) {
        self.tokenStore = tokenStore
        self.authenticationManager = authenticationManager
        self.settings = settings
    }

    // MARK: - Token Operations

    func loadTokens() {
        tokenStore.load()
    }

    func deleteToken(_ token: Token) {
        guard let index = tokenStore.tokens.firstIndex(where: { $0.id == token.id }) else { return }
        tokenStore.delete(at: IndexSet(integer: index))
        ClipboardManager.shared.provideHapticFeedback(.medium)
    }

    func incrementCounter(for token: Token) {
        guard !hotpIncrementInProgress,
              token.type == .hotp,
              let index = tokenStore.tokens.firstIndex(where: { $0.id == token.id }) else { return }
        hotpIncrementInProgress = true
        defer { hotpIncrementInProgress = false }
        var updated = tokenStore.tokens
        updated[index].incrementCounter()
        try? tokenStore.update(updated)
    }

    func toggleFavorite(_ token: Token) {
        guard let index = tokenStore.tokens.firstIndex(where: { $0.id == token.id }) else { return }
        var updated = tokenStore.tokens
        updated[index].isFavorite.toggle()
        updated[index].touch()
        ClipboardManager.shared.provideHapticFeedback(updated[index].isFavorite ? .success : .medium)
        Task { @MainActor in try? tokenStore.update(updated) }
    }

    // MARK: - New Token Tracking

    func trackNewTokens() {
        let added = Set(tokenStore.tokens.map(\.id)).subtracting(snapshotIDsBeforeAdd)
        newTokenIDs.formUnion(added)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.newTokenIDs.subtract(added)
        }
        checkBackupNudge()
    }

    func captureSnapshotBeforeAdd() {
        snapshotIDsBeforeAdd = Set(tokenStore.tokens.map(\.id))
    }

    // MARK: - Backup Nudge

    private func checkBackupNudge() {
        guard !showBackupNudge else { return }
        let count = tokenStore.tokens.count
        if settings.backupNudgeCount == 0, count >= 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.showBackupNudge else { return }
                showBackupNudge = true
            }
        } else if settings.backupNudgeCount == 1, count >= 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.showBackupNudge else { return }
                showBackupNudge = true
            }
        }
    }

    func handleBackupLater() {
        settings.backupNudgeCount += 1
        showBackupNudge = false
    }

    func handleBackupExport() {
        settings.backupNudgeCount += 1
        showBackupNudge = false
        showExportSheet = true
    }

    // MARK: - Copy to Clipboard

    func copyCodeToClipboard(from token: Token) {
        if let code = try? token.generateCode() {
            ClipboardManager.shared.copyToClipboard(code, autoClearDelay: 30)
            ClipboardManager.shared.provideHapticFeedback(.success)
            showCopyToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showCopyToast = false
            }
        }
    }

    // MARK: - Token Movement (for reordering)

    func moveTokens(fromOffsets: IndexSet, toOffset: Int, in tokens: [Token]) {
        tokenStore.move(fromOffsets: fromOffsets, toOffset: toOffset, in: tokens)
    }

    // MARK: - Helper Methods

    func isTokenNew(_ token: Token) -> Bool {
        newTokenIDs.contains(token.id)
    }
}

// MARK: - TokenGroup

struct TokenGroup: Identifiable {
    let id: String
    let title: String?
    let tokens: [Token]
}
