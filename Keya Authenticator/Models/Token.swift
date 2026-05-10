import CryptoKit
import Foundation

struct Token: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var issuer: String?

    var secret: Data {
        secretStorage.prefix(secretLength)
    }

    var algorithm: Algorithm
    var digits: Int
    var type: TokenType

    var period: Int?

    var counter: UInt64?

    // MARK: - New fields (backward-compatible, all optional in storage)

    var notes: String?
    var isFavorite: Bool
    var groupName: String?

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Heap-backed secret storage

    private var secretStorage: Data

    private var secretLength: Int

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        issuer: String? = nil,
        secret: Data,
        algorithm: Algorithm = .sha1,
        digits: Int = 6,
        type: TokenType = .totp,
        period: Int? = 30,
        counter: UInt64? = nil,
        notes: String? = nil,
        isFavorite: Bool = false,
        groupName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.issuer = issuer
        secretLength = secret.count
        secretStorage = Token.paddedHeap(secret)
        self.algorithm = algorithm
        self.digits = digits
        self.type = type
        self.notes = notes
        self.isFavorite = isFavorite
        self.groupName = groupName

        switch type {
        case .totp:
            self.period = period ?? 30
            self.counter = nil
        case .hotp:
            self.period = nil
            self.counter = counter ?? 0
        }

        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func touch() {
        updatedAt = Date()
    }

    mutating func incrementCounter() {
        guard type == .hotp, let c = counter else { return }
        counter = c + 1
        touch()
    }

    var displayName: String {
        if let issuer, !issuer.isEmpty { return "\(issuer): \(name)" }
        return name
    }

    mutating func zeroSecret() {
        // Zero the bytes in-place before releasing the reference.
        // Note: Swift Data has copy-on-write semantics — if secretStorage was copied
        // elsewhere, only this instance's backing buffer is zeroed here. That is still
        // strictly better than replacing the reference without zeroing.
        secretStorage.withUnsafeMutableBytes { ptr in
            _ = ptr.initializeMemory(as: UInt8.self, repeating: 0)
        }
        secretLength = 0
        secretStorage = Data(count: 16)
    }

    // MARK: - Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, name, issuer, secret, algorithm, digits, type
        case period, counter
        case notes, isFavorite, groupName
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer)
        let secretStr = try c.decode(String.self, forKey: .secret)
        guard let secretData = secretStr.base32DecodedData else { throw TokenError.invalidBase32 }
        secretLength = secretData.count
        secretStorage = Token.paddedHeap(secretData)
        algorithm = try c.decode(Algorithm.self, forKey: .algorithm)
        let rawDigits = try c.decode(Int.self, forKey: .digits)
        digits = (rawDigits == 6 || rawDigits == 8) ? rawDigits : 6
        type = try c.decode(TokenType.self, forKey: .type)
        let rawPeriod = try c.decodeIfPresent(Int.self, forKey: .period)
        let rawCounter = try c.decodeIfPresent(UInt64.self, forKey: .counter)
        // Normalize period/counter by token type — matches the failable init's logic.
        switch type {
        case .totp:
            period = rawPeriod ?? 30
            counter = nil
        case .hotp:
            period = nil
            counter = rawCounter ?? 0
        }
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(issuer, forKey: .issuer)
        try c.encode(secret.base32EncodedString, forKey: .secret)
        try c.encode(algorithm, forKey: .algorithm)
        try c.encode(digits, forKey: .digits)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(period, forKey: .period)
        try c.encodeIfPresent(counter, forKey: .counter)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(groupName, forKey: .groupName)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Heap allocation

    private static func paddedHeap(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        let padCount = max(data.count, 16) - data.count
        var result = data
        if padCount > 0 {
            result.append(contentsOf: [UInt8](repeating: 0, count: padCount))
        }
        return result
    }
}
