import SwiftUI

struct AuthenticationView: View {
    @State private var viewModel: AuthenticationViewModel
    let onUnlock: () -> Void

    @State private var pinFocused = false
    @State private var shakeTrigger = 0
    @State private var contentOpacity: Double
    @State private var showBiometricChangedAlert = false
    @State private var biometricPromptPending = false
    @Environment(\.scenePhase) private var scenePhase

    init(authenticationManager: AuthenticationManager, settings: AppSettings, onUnlock: @escaping () -> Void) {
        let viewModel = AuthenticationViewModel(authenticationManager: authenticationManager, settings: settings)
        viewModel.onUnlock = onUnlock
        _viewModel = State(initialValue: viewModel)
        self.onUnlock = onUnlock

        let willTrigger = settings.useBiometricAuthentication
            && settings.biometricActivated
            && authenticationManager.isBiometricAvailable
        _contentOpacity = State(initialValue: willTrigger ? 0 : 1)
    }

    private var willAutoTriggerBiometric: Bool {
        viewModel.settings.useBiometricAuthentication
            && viewModel.settings.biometricActivated
            && viewModel.biometricAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("AppIconImage").resizable().aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            Text("app.name").font(.title2.weight(.medium)).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "Enter PIN to unlock")).font(.subheadline).foregroundColor(.secondary).padding(
                .bottom,
                32
            )
            .accessibilityAddTraits(.isHeader)

            PINEntryView(
                pin: $viewModel.pinText,
                isFocused: $pinFocused,
                errorMessage: viewModel.errorMessage,
                shakeTrigger: shakeTrigger,
                onComplete: { viewModel.authenticateWithPIN() }
            )

            Spacer()

            if viewModel.settings.useBiometricAuthentication,
               viewModel.settings.biometricActivated,
               viewModel.biometricAvailable
            {
                Button { authenticateWithBiometrics() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.biometricIcon)
                        Text(String(localized: "Unlock with \(viewModel.biometricDisplayName)"))
                    }
                    .font(.subheadline.weight(.medium)).foregroundColor(.blue)
                }
                .padding(.bottom, 24)
                .accessibilityLabel(String(localized: "Unlock with \(viewModel.biometricDisplayName)"))
            } else {
                Spacer().frame(height: 24)
            }
        }
        .opacity(contentOpacity)
        .contentShape(Rectangle())
        .onTapGesture { pinFocused = true }
        .onAppear {
            viewModel.checkLockoutOnAppear()
            if willAutoTriggerBiometric {
                contentOpacity = 0
                if scenePhase == .active {
                    authenticateWithBiometrics()
                } else {
                    biometricPromptPending = true
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pinFocused = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, biometricPromptPending else { return }
            biometricPromptPending = false
            authenticateWithBiometrics()
        }
        .onChange(of: viewModel.errorMessage) { _, err in
            if let error = err, !error.isEmpty {
                shakeTrigger += 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "PIN unlock screen"))
        .alert("Biometric database changed", isPresented: $showBiometricChangedAlert) {
            Button("OK", role: .cancel) { onUnlock() }
        } message: {
            Text(
                "The Face ID / Touch ID database on this device has changed since your last login. Biometric unlock has been disabled as a security precaution. You can re-enable it in Settings → App lock once you've confirmed the change was made by you."
            )
        }
        .onChange(of: viewModel.biometricChangedDetected) { _, detected in
            guard detected else { return }
            showBiometricChangedAlert = true
        }
    }

    private func authenticateWithBiometrics() {
        Task {
            await viewModel.authenticateWithBiometrics()
            await MainActor.run {
                if viewModel.errorMessage != nil {
                    withAnimation(.easeIn(duration: 0.2)) { contentOpacity = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pinFocused = true }
                }
            }
        }
    }
}
