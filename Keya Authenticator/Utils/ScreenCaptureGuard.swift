import UIKit

/// Detects active screen recording or AirPlay mirroring and publishes the state
/// so the app can overlay a privacy screen when the display is being captured.
@Observable
final class ScreenCaptureGuard {
    private(set) var isCapturing: Bool
    private var observer: (any NSObjectProtocol)?

    init() {
        isCapturing = UIScreen.main.isCaptured
        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.isCapturing = (notification.object as? UIScreen)?.isCaptured ?? false
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
