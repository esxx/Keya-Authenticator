import SwiftUI

struct PINVerifySheet: View {
    let authenticationManager: AuthenticationManager
    let onVerified: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var pinFocused: Bool
    @State private var pinText = ""
    @State private var errorMessage: String? = nil
    @State private var shakeOffset: CGFloat = 0
    @State private var isVerifying = false

    private let pinLength = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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

                HStack(spacing: 16) {
                    ForEach(0 ..< pinLength, id: \.self) { i in
                        Circle()
                            .fill(i < pinText.count ? Color.primary : Color.clear)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(
                                i < pinText.count ? Color.primary : Color(.separator),
                                lineWidth: 1.5
                            ))
                    }
                }
                .offset(x: shakeOffset)
                .padding(.bottom, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                        .padding(.bottom, 4)
                }

                Spacer()

                TextField("", text: $pinText)
                    .keyboardType(.numberPad)
                    .focused($pinFocused)
                    .opacity(0.001)
                    .frame(width: 1, height: 1)
                    .onChange(of: pinText) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(pinLength))
                        if filtered != newValue { pinText = filtered
                            return
                        }
                        if filtered.count == pinLength {
                            verifyPIN()
                        }
                    }

                Spacer().frame(height: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Constants.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onVerified(false)
                    }
                }
            }
            .onAppear {
                if let seconds = authenticationManager.pinLockoutSecondsRemaining(), seconds > 0 {
                    if seconds >= 60 {
                        errorMessage = "Too many attempts. Try again in \(seconds / 60)m \(seconds % 60)s."
                    } else {
                        errorMessage = "Too many attempts. Try again in \(seconds)s."
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pinFocused = true
                }
            }
            .onChange(of: errorMessage) { _, errorMessage in
                if let error = errorMessage, !error.isEmpty {
                    shakeDots()
                }
            }
        }
    }

    private func verifyPIN() {
        guard !pinText.isEmpty, !isVerifying else { return }

        isVerifying = true
        errorMessage = nil

        do {
            try authenticationManager.authenticateWithPIN(pinText)
            pinText = ""
            isVerifying = false
            onVerified(true)
        } catch let error as AuthenticationManager.AuthenticationError {
            errorMessage = error.localizedDescription
            pinText = ""
            isVerifying = false
        } catch {
            errorMessage = "PIN verification failed"
            pinText = ""
            isVerifying = false
        }
    }

    private func shakeDots() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.default) { shakeOffset = -10 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.default) { shakeOffset = 6 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.default) { shakeOffset = 0 } }
    }
}

#Preview {
    PINVerifySheet(
        authenticationManager: AuthenticationManager(),
        onVerified: { _ in }
    )
}
