import StoreKit
import SwiftUI

struct TipJarView: View {
    @State private var tipStore = TipStore()
    @Environment(\.dismiss) private var dismiss

    private struct Tier {
        let productID: String
        let emoji: String
        let label: LocalizedStringKey
    }

    private let tiers: [Tier] = [
        Tier(productID: "ee.exx.KeyaAuthenticator.tip.small", emoji: "☕️", label: "Buy me a coffee"),
        Tier(productID: "ee.exx.KeyaAuthenticator.tip.medium", emoji: "🍕", label: "Buy me a pizza"),
        Tier(productID: "ee.exx.KeyaAuthenticator.tip.large", emoji: "🍽️", label: "Treat me to a family dinner"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if tipStore.thankYouVisible {
                    thankYouView
                } else {
                    tipListView
                }
            }
            .background(Constants.Colors.background)
            .navigationTitle("Support development")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await tipStore.load() }
    }

    // MARK: - Tip list

    private var tipListView: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.pink)
                    Text(
                        "Keya Authenticator is free and open-source with no ads, no tracking, and no subscription. If it gives you peace of mind, a small tip means a lot."
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            Section {
                if tipStore.products.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(tipStore.products, id: \.id) { product in
                        tipRow(product: product)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func tipRow(product: Product) -> some View {
        let tier = tiers.first { $0.productID == product.id }
        return Button {
            Task { await tipStore.purchase(product) }
        } label: {
            HStack(spacing: 14) {
                Text(tier?.emoji ?? "💝")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    if let tier {
                        Text(tier.label)
                            .font(.body)
                            .foregroundStyle(.primary)
                    } else {
                        Text(product.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    Text(product.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.pink)
            }
        }
        .disabled(tipStore.isPurchasing)
    }

    // MARK: - Thank you

    private var thankYouView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            Text("Thank You!")
                .font(.title.bold())
            Text("Your support keeps Keya Authenticator independent and ad-free. It genuinely makes a difference.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            Spacer()
        }
    }
}

#Preview {
    TipJarView()
}
