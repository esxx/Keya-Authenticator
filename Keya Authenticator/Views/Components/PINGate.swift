import SwiftUI

struct PINGate<Content: View>: View {
    let authenticationManager: AuthenticationManager
    let content: () -> Content

    @State private var isUnlocked: Bool

    init(
        authenticationManager: AuthenticationManager,
        isRequired: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.authenticationManager = authenticationManager
        self.content = content
        _isUnlocked = State(initialValue: !isRequired)
    }

    var body: some View {
        if isUnlocked {
            content()
        } else {
            PINPrompt(authenticationManager: authenticationManager) { isUnlocked = true }
        }
    }
}
