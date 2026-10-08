import ObjectiveC
import SwiftUI
import UIKit

struct SwipeDismissAttempt: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    final class Proxy: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void = {}
        var original: UIAdaptivePresentationControllerDelegate?

        private static let associationToken = NSObject()
        static let associationKey = UnsafeRawPointer(Unmanaged.passUnretained(associationToken).toOpaque())

        static func install(on presentation: UIPresentationController, onAttempt: @escaping () -> Void) {
            let proxy: Proxy
            if let existing = objc_getAssociatedObject(presentation, associationKey) as? Proxy {
                proxy = existing
            } else {
                proxy = Proxy()
                objc_setAssociatedObject(presentation, associationKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            proxy.onAttempt = onAttempt
            if presentation.delegate !== proxy {
                if !(presentation.delegate is Proxy) {
                    proxy.original = presentation.delegate
                }
                presentation.delegate = proxy
            }
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        override func responds(to aSelector: Selector?) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector?) -> Any? {
            if original?.responds(to: aSelector) == true {
                return original
            }
            return super.forwardingTarget(for: aSelector)
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let onAttempt = onAttempt
        DispatchQueue.main.async {
            var top = controller
            while let parent = top.parent {
                top = parent
            }
            guard let presentation = top.presentationController else { return }
            Proxy.install(on: presentation, onAttempt: onAttempt)
        }
    }
}
