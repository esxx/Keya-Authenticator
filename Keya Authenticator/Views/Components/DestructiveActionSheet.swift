import SwiftUI
import UIKit

struct DestructiveActionSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let title: String?
    let message: String?
    let actionTitle: String
    let action: () -> Void

    final class Coordinator {
        nonisolated deinit {}

        var isShowing = false
        weak var sheet: UIAlertController?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.isShowing = false
        coordinator.sheet?.dismiss(animated: false)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        if !isPresented, context.coordinator.isShowing {
            context.coordinator.isShowing = false
            context.coordinator.sheet?.dismiss(animated: false)
            return
        }
        guard isPresented, !context.coordinator.isShowing else { return }
        context.coordinator.isShowing = true

        let coordinator = context.coordinator
        let binding = $isPresented
        let sheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: actionTitle, style: .destructive) { [action] _ in
            coordinator.isShowing = false
            action()
            binding.wrappedValue = false
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
            coordinator.isShowing = false
            binding.wrappedValue = false
        })
        coordinator.sheet = sheet

        DispatchQueue.main.async {
            guard coordinator.isShowing, coordinator.sheet === sheet else { return }
            let window = controller.view.window ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            guard var top = window?.rootViewController else {
                coordinator.isShowing = false
                binding.wrappedValue = false
                return
            }
            while let next = top.presentedViewController {
                top = next
            }
            top.present(sheet, animated: true) {
                if !coordinator.isShowing || coordinator.sheet !== sheet {
                    sheet.dismiss(animated: false)
                }
            }
        }
    }
}

extension View {
    func destructiveActionSheet(
        isPresented: Binding<Bool>,
        title: String? = nil,
        message: String? = nil,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        background(
            DestructiveActionSheet(
                isPresented: isPresented,
                title: title,
                message: message,
                actionTitle: actionTitle,
                action: action
            )
        )
    }
}
