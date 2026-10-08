import SwiftUI

struct PINAuthSheet: View {
    let authenticationManager: AuthenticationManager
    let onSuccess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            PINPrompt(authenticationManager: authenticationManager, onSuccess: onSuccess)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                }
        }
    }
}
