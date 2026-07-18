import Foundation
import LocalAuthentication
import SwiftUI

@Observable
final class TokenStore {
    // MARK: - Properties

    private(set) var tokens: [Token] = []

    private var sortedIDs: [UUID] = []
    private let sortOrderKey = "tokenSortOrder"

    // MARK: - Load / Clear

    func load(using authContext: LAContext? = nil) throws {
        var loaded = try KeychainManager.loadAllTokens(using: authContext)
        applySort(to: &loaded)
        if loaded != tokens {
            tokens = loaded
        }
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

    // MARK: - Token Mutations

    func update(_ newTokens: [Token]) throws {
        let oldIDs = Set(tokens.map(\.id))

        var bestByContent: [String: Token] = [:]
        for token in newTokens {
            let key = token.contentKey
            guard let current = bestByContent[key] else {
                bestByContent[key] = token
                continue
            }
            let currentIsExisting = oldIDs.contains(current.id)
            let tokenIsExisting = oldIDs.contains(token.id)
            if currentIsExisting, !tokenIsExisting {
                continue
            }
            if tokenIsExisting, !currentIsExisting {
                bestByContent[key] = token
                continue
            }
            if token.updatedAt > current.updatedAt {
                bestByContent[key] = token
            }
        }
        var deduped = Array(bestByContent.values)

        var seenDupIDs = Set<UUID>()
        deduped = deduped.reversed().filter { token in
            if oldIDs.contains(token.id) {
                return true
            }
            return seenDupIDs.insert(token.id).inserted
        }.reversed()

        let newIDs = Set(deduped.map(\.id))
        var orphanDeleteError: Error?
        for id in oldIDs.subtracting(newIDs) {
            do {
                try KeychainManager.deleteToken(id: id)
            } catch {
                if orphanDeleteError == nil {
                    orphanDeleteError = error
                }
            }
        }
        for token in deduped {
            try KeychainManager.saveToken(token)
        }
        applySort(to: &deduped)
        tokens = deduped
        if let orphanDeleteError {
            throw orphanDeleteError
        }
    }

    func delete(at indices: IndexSet) throws {
        let sorted = indices.sorted(by: >)
        var updated = tokens
        var firstError: Error?
        for index in sorted where index < updated.count {
            do {
                try KeychainManager.deleteToken(id: updated[index].id)
                updated.remove(at: index)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        applySort(to: &updated)
        tokens = updated
        if let firstError {
            throw firstError
        }
    }

    func deleteAll() {
        var snapshot = tokens
        tokens = []
        sortedIDs = []
        UserDefaults.standard.removeObject(forKey: sortOrderKey)
        try? KeychainManager.deleteAllTokens()
        for i in 0 ..< snapshot.count where !snapshot[i].secret.isEmpty {
            snapshot[i].zeroSecret()
        }
    }
}
