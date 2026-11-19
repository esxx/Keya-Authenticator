import StoreKit

@Observable
@MainActor
final class TipStore {
    nonisolated deinit {}

    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var thankYouVisible = false
    private(set) var loadFailed = false
    var purchaseErrorMessage: String?

    static let productIDs = [
        "ee.exx.KeyaAuthenticator.tip.small",
        "ee.exx.KeyaAuthenticator.tip.medium",
        "ee.exx.KeyaAuthenticator.tip.large",
    ]

    static func finishTransactionUpdates() async {
        for await result in Transaction.updates {
            if case let .verified(transaction) = result {
                await transaction.finish()
            }
        }
    }

    func load() async {
        guard products.isEmpty else { return }
        loadFailed = false
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.price < $1.price }
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case let .success(verification) = result,
               case let .verified(transaction) = verification
            {
                await transaction.finish()
                thankYouVisible = true
            }
        } catch StoreKitError.userCancelled {
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }
}
