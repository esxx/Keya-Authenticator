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

    func load(using authContext: LAContext? = nil) {
        do {
            var loaded = try KeychainManager.loadAllTokens(using: authContext)
            applySort(to: &loaded)
            tokens = loaded
        } catch {
            // On a transient Keychain error, preserve whatever is already in memory.
            // Never wipe a populated vault because of a temporary read failure.
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

        var seenKeys = Set<String>()
        var keyToIndex: [String: Int] = [:]
        var deduped: [Token] = []
        for token in newTokens {
            let key = contentKey(for: token)
            if oldIDs.contains(token.id) {
                keyToIndex[key] = deduped.count
                seenKeys.insert(key)
                deduped.append(token)
                continue
            }
            if seenKeys.contains(key) {
                continue // discard the duplicate; keep the first-seen token's metadata intact
            }
            keyToIndex[key] = deduped.count
            seenKeys.insert(key)
            deduped.append(token)
        }

        var seenDupIDs = Set<UUID>()
        deduped = deduped.reversed().filter { token in
            if oldIDs.contains(token.id) { return true }
            return seenDupIDs.insert(token.id).inserted
        }.reversed()

        let newIDs = Set(deduped.map(\.id))
        for id in oldIDs.subtracting(newIDs) {
            try? KeychainManager.deleteToken(id: id)
        }
        for token in deduped {
            try KeychainManager.saveToken(token)
        }
        applySort(to: &deduped)
        tokens = deduped
    }

    private func contentKey(for token: Token) -> String {
        let secretHex = token.secret.map { String(format: "%02x", $0) }.joined()
        return "\(secretHex)|\(token.algorithm.rawValue)|\(token.digits)|\(token.period ?? 0)"
    }

    func delete(at indices: IndexSet) {
        let sorted = indices.sorted(by: >)
        var updated = tokens
        for index in sorted where index < updated.count {
            do {
                try KeychainManager.deleteToken(id: updated[index].id)
                updated.remove(at: index)
            } catch {}
        }
        applySort(to: &updated)
        tokens = updated
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
