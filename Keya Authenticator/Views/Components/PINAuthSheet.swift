import SwiftUI

struct PINAuthSheet: View {
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var attempt: PINAttempt
    @State private var pinText = ""
    @State private var pinFocused = false

    init(
        authenticationManager: AuthenticationManager,
        onSuccess: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _attempt = State(initialValue: PINAttempt(authenticationManager: authenticationManager))
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 20)
                    .accessibilityHidden(true)

                Text("app.name")
                    .font(.title2.weight(.medium))
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter PIN to unlock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 32)
                    .accessibilityAddTraits(.isHeader)

                PINEntryView(
                    pin: $pinText,
                    isFocused: $pinFocused,
                    errorMessage: attempt.message,
                    shakeTrigger: attempt.failureCount,
                    onComplete: verify
                )

                Spacer()

                Spacer().frame(height: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Constants.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { pinFocused = true }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pinFocused = true }
                attempt.showLockoutIfActive()
            }
        }
    }

    private func verify() {
        guard attempt.submit(pinText) != nil else {
            pinText = ""
            return
        }
        onSuccess()
    }
}
