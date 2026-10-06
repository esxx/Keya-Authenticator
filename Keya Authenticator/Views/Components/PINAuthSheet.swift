import SwiftUI

struct PINAuthSheet: View {
    let authenticationManager: AuthenticationManager
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var pinText = ""
    @State private var pinError: String? = nil
    @State private var lockoutSecondsRemaining: Int? = nil
    @State private var shakeTrigger = 0
    @State private var pinFocused = false

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
                    errorMessage: pinError,
                    shakeTrigger: shakeTrigger,
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
                checkLockout()
            }
            .task(id: lockoutSecondsRemaining) {
                guard let seconds = lockoutSecondsRemaining, seconds > 0 else { return }
                try? await Task.sleep(for: .seconds(1))
                let remaining = seconds - 1
                if remaining > 0 {
                    lockoutSecondsRemaining = remaining
                    pinError = AuthenticationManager.lockoutMessage(seconds: remaining)
                } else {
                    lockoutSecondsRemaining = nil
                    pinError = nil
                }
            }
        }
    }

    private func checkLockout() {
        guard let seconds = authenticationManager.pinLockoutSecondsRemaining(), seconds > 0 else { return }
        lockoutSecondsRemaining = seconds
        pinError = AuthenticationManager.lockoutMessage(seconds: seconds)
    }

    private func verify() {
        pinError = nil
        do {
            try authenticationManager.authenticateWithPIN(pinText)
            onSuccess()
        } catch let error as AuthenticationManager.AuthenticationError {
            pinError = error.localizedDescription
            pinText = ""
            shakeTrigger += 1
            if let seconds = authenticationManager.pinLockoutSecondsRemaining(), seconds > 0 {
                lockoutSecondsRemaining = seconds
            }
        } catch {
            pinError = String(localized: "PIN verification failed. Please try again.")
            pinText = ""
            shakeTrigger += 1
        }
    }
}
