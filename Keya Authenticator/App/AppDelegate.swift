import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    nonisolated deinit {}

    private var transactionUpdates: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        transactionUpdates = Task { await TipStore.finishTransactionUpdates() }
        return true
    }

    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
