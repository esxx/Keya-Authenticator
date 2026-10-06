import AuthenticationServices
import Foundation
import LocalAuthentication
import os
import SwiftUI

// MARK: - AutoFill identity store

protocol AutoFillIdentityStore {
    func isEnabled() async -> Bool
    func replaceIdentities(_ identities: [ASOneTimeCodeCredentialIdentity]) async throws
}

struct SystemAutoFillIdentityStore: AutoFillIdentityStore {
    func isEnabled() async -> Bool {
        await ASCredentialIdentityStore.shared.state().isEnabled
    }

    func replaceIdentities(_ identities: [ASOneTimeCodeCredentialIdentity]) async throws {
        try await ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities)
    }
}

// MARK: - Errors

enum TokenStoreError: LocalizedError, Equatable {
    case tokenNotFound
    case idChanged

    var errorDescription: String? {
        switch self {
        case .tokenNotFound: String(localized: "Token not found")
        case .idChanged: String(localized: "Your token couldn't be saved. Please try again.")
        }
    }
}

@Observable
final class TokenStore {
    // MARK: - Properties

    private(set) var tokens: [Token] = []
    private(set) var unreadableTokenCount = 0

    private var sortedIDs: [UUID] = []
    private let sortOrderKey = "tokenSortOrder"

    private let identityStore: AutoFillIdentityStore
    private(set) var autoFillSync: Task<Void, Never>?

    init(identityStore: AutoFillIdentityStore = SystemAutoFillIdentityStore()) {
        self.identityStore = identityStore
    }

    // MARK: - Load / Clear

    func load(using authContext: LAContext? = nil) throws {
        let result = try KeychainManager.loadAllTokensCountingUnreadable(using: authContext)
        var loaded = result.tokens
        unreadableTokenCount = result.unreadable
        applySort(to: &loaded)
        if loaded != tokens {
            tokens = loaded
        }
        syncAutoFillIdentities()
    }

    // MARK: - Sort order

    private func applySort(to list: inout [Token]) {
        loadSortOrder()
        let existingIDs = Set(list.map(\.id))
        let knownIDs = Set(sortedIDs)
        let newIDs = list.filter { !knownIDs.contains($0.id) }.map(\.id)
        sortedIDs.append(contentsOf: newIDs)
        sortedIDs = sortedIDs.filter { existingIDs.contains($0) }
        var seen = Set<UUID>()
        sortedIDs = sortedIDs.filter { seen.insert($0).inserted }
        saveSortOrder()
        var rank: [UUID: Int] = [:]
        rank.reserveCapacity(sortedIDs.count)
        for (idx, id) in sortedIDs.enumerated() {
            rank[id] = idx
        }
        list.sort { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }

    private func loadSortOrder() {
        guard let data = UserDefaults.standard.data(forKey: sortOrderKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        sortedIDs = ids
    }

    private func saveSortOrder() {
        guard let data = try? JSONEncoder().encode(sortedIDs) else { return }
        UserDefaults.standard.set(data, forKey: sortOrderKey)
    }

    func move(fromOffsets: IndexSet, toOffset: Int, in sectionTokens: [Token]) {
        var sectionIDs = sectionTokens.map(\.id)
        sectionIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        let sectionIDSet = Set(sectionIDs)
        var sectionCursor = 0
        for i in sortedIDs.indices where sectionIDSet.contains(sortedIDs[i]) {
            sortedIDs[i] = sectionIDs[sectionCursor]
            sectionCursor += 1
        }
        saveSortOrder()

        var rank: [UUID: Int] = [:]
        rank.reserveCapacity(sortedIDs.count)
        for (idx, id) in sortedIDs.enumerated() {
            rank[id] = idx
        }
        var reordered = tokens
        reordered.sort { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        tokens = reordered
    }

    func clear() {
        var snapshot = tokens
        tokens = []
        for i in 0 ..< snapshot.count where !snapshot[i].secret.isEmpty {
            snapshot[i].zeroSecret()
        }
    }

    // MARK: - Duplicate detection

    struct DuplicateTokenPair {
        let new: Token
        let existing: Token
    }

    func existingDuplicates(of candidates: [Token]) -> [DuplicateTokenPair] {
        let byContent = Dictionary(tokens.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
        return candidates.compactMap { candidate in
            guard let match = byContent[candidate.contentKey], match.id != candidate.id else { return nil }
            return DuplicateTokenPair(new: candidate, existing: match)
        }
    }

    // MARK: - Token Mutations

    struct AddResult {
        let added: Int
        let alreadyInVault: Int
    }

    @discardableResult
    func add(_ newTokens: [Token]) throws -> AddResult {
        var seenIDs = Set(tokens.map(\.id))
        let toWrite = newTokens.filter { seenIDs.insert($0.id).inserted }
        for token in toWrite {
            do {
                try KeychainManager.saveToken(token)
            } catch {
                try? load()
                throw error
            }
        }
        var updated = tokens + toWrite
        applySort(to: &updated)
        tokens = updated
        syncAutoFillIdentities()
        return AddResult(added: toWrite.count, alreadyInVault: newTokens.count - toWrite.count)
    }

    func update(id: UUID, _ change: (inout Token) -> Void) throws {
        guard let index = tokens.firstIndex(where: { $0.id == id }) else {
            throw TokenStoreError.tokenNotFound
        }
        var token = tokens[index]
        change(&token)
        guard token.id == id else { throw TokenStoreError.idChanged }
        token.touch()
        try KeychainManager.saveToken(token)
        tokens[index] = token
        syncAutoFillIdentities()
    }

    func delete(id: UUID) throws {
        try KeychainManager.deleteToken(id: id)
        var updated = tokens
        updated.removeAll { $0.id == id }
        applySort(to: &updated)
        tokens = updated
        syncAutoFillIdentities()
    }

    func deleteAll() throws {
        do {
            try KeychainManager.deleteAllTokens()
        } catch {
            try? load()
            throw error
        }
        var snapshot = tokens
        tokens = []
        unreadableTokenCount = 0
        sortedIDs = []
        UserDefaults.standard.removeObject(forKey: sortOrderKey)
        syncAutoFillIdentities()
        for i in 0 ..< snapshot.count where !snapshot[i].secret.isEmpty {
            snapshot[i].zeroSecret()
        }
    }

    // MARK: - AutoFill

    private func syncAutoFillIdentities() {
        let previous = autoFillSync
        autoFillSync = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let identities = tokens.compactMap { token -> ASOneTimeCodeCredentialIdentity? in
                guard token.type == .totp, let website = token.website else { return nil }
                let label = token.issuer.flatMap { $0.isEmpty ? nil : $0 } ?? website
                return ASOneTimeCodeCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: website, type: .domain),
                    label: label,
                    recordIdentifier: token.id.uuidString
                )
            }
            guard await identityStore.isEnabled() else { return }
            do {
                try await identityStore.replaceIdentities(identities)
            } catch {
                Logger(subsystem: Constants.keychainService, category: "AutoFill")
                    .error("Updating AutoFill suggestions failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
