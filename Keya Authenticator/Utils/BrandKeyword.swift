import Foundation

enum BrandKeyword {
    private static let secondLevelLabels: Set<String> = [
        "co", "com", "net", "org", "ac", "gov", "edu",
    ]

    static func extract(fromHost host: String) -> String {
        let parts = host.lowercased()
            .split(separator: ".")
            .filter { $0 != "www" }
        guard parts.count >= 2 else { return host.lowercased() }

        var brandIndex = parts.count - 2
        if parts.count >= 3, secondLevelLabels.contains(String(parts[brandIndex])) {
            brandIndex -= 1
        }
        return String(parts[brandIndex])
    }
}
