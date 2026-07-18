import SwiftUI

struct AuthenticationView: View {
    @State private var viewModel: AuthenticationViewModel
    let onUnlock: () -> Void

    @FocusState private var pinFocused: Bool
    @State private var shakeOffset: CGFloat = 0
    @State private var contentOpacity: Double
    @State private var showBiometricChangedAlert = false

    private let pinLength = 6

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

            HStack(spacing: 16) {
                ForEach(0 ..< pinLength, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.pinText.count ? Color.primary : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(
                            i < viewModel.pinText.count ? Color.primary : Color(.separator),
                            lineWidth: 1.5
                        ))
                        .accessibilityLabel(i < viewModel.pinText.count ?
                            String(localized: "Digit \(i + 1) entered") :
                            String(localized: "Digit \(i + 1) empty"))
                }
            }
            .offset(x: shakeOffset).padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "PIN entry dots"))
            .accessibilityValue(String(localized: "\(viewModel.pinText.count) of \(pinLength) digits entered"))

            if let err = viewModel.errorMessage {
                Text(err).font(.caption).foregroundColor(.red).transition(.opacity).padding(.bottom, 4)
                    .accessibilityLabel(String(localized: "Error"))
                    .accessibilityValue(err)
            }

            Spacer()

            TextField("", text: $viewModel.pinText)
                .keyboardType(.numberPad)
                .focused($pinFocused)
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)

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
                authenticateWithBiometrics()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pinFocused = true }
            }
        }
        .onChange(of: viewModel.pinText) { _, newValue in
            let filtered = String(newValue.filter(\.isNumber).prefix(pinLength))
            if filtered != newValue {
                viewModel.pinText = filtered
                return
            }
            if filtered.count == pinLength {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    viewModel.authenticateWithPIN()
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { _, err in
            if let error = err, !error.isEmpty {
                shakeDots()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "PIN unlock screen"))
        .alert("Biometric database changed", isPresented: $showBiometricChangedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "The Face ID / Touch ID database on this device has changed since your last login. Biometric unlock has been disabled as a security precaution. You can re-enable it in Settings → App lock once you've confirmed the change was made by you."
            )
        }
        .onChange(of: viewModel.biometricChangedDetected) { _, detected in
            guard detected else { return }
            viewModel.settings.useBiometricAuthentication = false
            viewModel.settings.biometricActivated = false
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

    private func shakeDots() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.default) { shakeOffset = -10 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.default) { shakeOffset = 6 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.default) { shakeOffset = 0 } }
    }
}
