import SwiftUI

@Observable
final class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    func copyToClipboard(_ text: String, autoClearDelay: TimeInterval? = 30) {
        let pasteboard = UIPasteboard.general

        var options: [UIPasteboard.OptionsKey: Any] = [
            .localOnly: true, // never sync to other devices via Handoff
        ]
        if let delay = autoClearDelay, delay > 0 {
            options[.expirationDate] = Date().addingTimeInterval(delay)
        }

        pasteboard.setItems([[UIPasteboard.typeAutomatic: text]], options: options)
    }

    func clearClipboard() {
        UIPasteboard.general.items = []
    }
}

// MARK: - Haptic Feedback

extension ClipboardManager {
    func provideHapticFeedback(_ type: HapticType = .success) {
        switch type {
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
    }
}

enum HapticType {
    case success
    case warning
    case error
    case light
    case medium
    case heavy
}
