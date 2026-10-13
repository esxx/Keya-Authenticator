import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    nonisolated deinit {}

    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
