import SwiftUI
import UIKit

// MARK: - Share with a plaintext warning

extension View {
    func confirmingSecretShare(_ pendingImage: Binding<UIImage?>) -> some View {
        modifier(SecretShareConfirmation(pendingImage: pendingImage))
    }
}

private struct SecretShareConfirmation: ViewModifier {
    @Binding var pendingImage: UIImage?
    @State private var sharedImage: SharedImage?

    func body(content: Content) -> some View {
        content
            .alert("Unencrypted export", isPresented: Binding(
                get: { pendingImage != nil },
                set: {
                    if !$0 {
                        pendingImage = nil
                    }
                }
            )) {
                Button("Export", role: .destructive) {
                    if let image = pendingImage {
                        sharedImage = SharedImage(image: image)
                    }
                    pendingImage = nil
                }
                Button("Cancel", role: .cancel) { pendingImage = nil }
            } message: {
                Text(
                    "This backup will contain your token secrets in plain text. Store it in a secure location such as an encrypted disk or password manager. Consider using encrypted JSON instead."
                )
            }
            .sheet(item: $sharedImage) { shared in
                ActivityShareSheet(items: [shared.image])
            }
    }
}

private struct SharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
