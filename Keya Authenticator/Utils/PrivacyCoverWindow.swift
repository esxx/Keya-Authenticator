import SwiftUI
import UIKit

@MainActor
final class PrivacyCoverWindow {
    private var window: UIWindow?

    func setVisible(_ visible: Bool, colorScheme: ColorScheme?) {
        if visible {
            show(colorScheme: colorScheme)
        } else {
            hide()
        }
    }

    private func show(colorScheme: ColorScheme?) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        switch colorScheme {
        case .light: cover.overrideUserInterfaceStyle = .light
        case .dark: cover.overrideUserInterfaceStyle = .dark
        default: cover.overrideUserInterfaceStyle = .unspecified
        }
        cover.rootViewController = UIHostingController(rootView: PrivacyCoverView())
        cover.isHidden = false
        window = cover
    }

    private func hide() {
        guard let cover = window else { return }
        window = nil
        UIView.animate(withDuration: 0.25) {
            cover.alpha = 0
        } completion: { _ in
            cover.isHidden = true
        }
    }
}

// MARK: - Cover view

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Constants.Colors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("app.name")
                    .font(.title3.weight(.medium))
            }
        }
    }
}
