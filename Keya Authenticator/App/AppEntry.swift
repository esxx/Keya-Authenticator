import SwiftUI
import UniformTypeIdentifiers

@main
struct AppEntry: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var tokenStore = TokenStore()
    @State private var authenticationManager = AuthenticationManager()
    @State private var settings = AppSettings()
    @State private var appViewModel: AppCoordinator
    @State private var totpClock = TOTPClock()
    @State private var captureGuard = ScreenCaptureGuard()

    init() {
        let tokenStore = TokenStore()
        let authenticationManager = AuthenticationManager()
        let settings = AppSettings()
        _tokenStore = State(initialValue: tokenStore)
        _authenticationManager = State(initialValue: authenticationManager)
        _settings = State(initialValue: settings)
        _appViewModel = State(initialValue: AppCoordinator(
            tokenStore: tokenStore,
            authenticationManager: authenticationManager,
            settings: settings
        ))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch appViewModel.appState {
                case .loading:
                    Constants.Colors.background.ignoresSafeArea()

                case .pinSetup:
                    ZStack {
                        Constants.Colors.background.ignoresSafeArea()
                        PINSetupView(
                            authenticationManager: authenticationManager,
                            onComplete: { appViewModel.completePINSetup() }
                        )
                    }

                case .appUnlock:
                    ZStack {
                        Constants.Colors.background.ignoresSafeArea()
                        AuthenticationView(
                            authenticationManager: authenticationManager,
                            settings: settings,
                            onUnlock: { appViewModel.completeUnlock() }
                        )
                    }

                case .main:
                    MainContentView(
                        viewModel: appViewModel.mainContentViewModel,
                        onResetRequested: { appViewModel.resetEverything() }
                    )
                }

                if appViewModel.showPrivacyOverlay || captureGuard.isCapturing {
                    privacyOverlay
                        .transition(.opacity)
                }
            }
            .environment(totpClock)
            .preferredColorScheme(settings.appTheme.colorScheme)
            .onAppear {
                appViewModel.determineInitialState()
            }
            .onOpenURL { url in
                appViewModel.handleIncomingURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                appViewModel.showPrivacyOverlay = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                appViewModel.handleAppBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                appViewModel.handleAppBecameActive()
            }
        }
    }

    // MARK: - Privacy overlay view

    private var privacyOverlay: some View {
        ZStack {
            Constants.Colors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("app.name")
                    .font(.title3.weight(.medium))
            }
        }
    }
}

// MARK: - PINSetupView

struct PINSetupView: View {
    @Bindable var authenticationManager: AuthenticationManager
    let onComplete: () -> Void

    @State private var step: Step = .enter
    @State private var firstPIN: String = ""
    @State private var pinText: String = ""
    @FocusState private var pinFocused: Bool
    @State private var errorMessage: String? = nil
    @State private var shakeOffset: CGFloat = 0

    enum Step { case enter, confirm }

    private let pinLength = 6

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("AppIconImage").resizable().aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 20)

            Text("app.name").font(.title2.weight(.medium)).padding(.bottom, 4)

            Text(step == .enter ? String(localized: "Create a 6-digit PIN") : String(localized: "Confirm"))
                .font(.subheadline).foregroundColor(.secondary).padding(.bottom, 32)

            HStack(spacing: 16) {
                ForEach(0 ..< pinLength, id: \.self) { i in
                    Circle()
                        .fill(i < pinText.count ? Color.primary : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(i < pinText.count ? Color.primary : Color(.separator), lineWidth: 1.5))
                }
            }
            .offset(x: shakeOffset).padding(.bottom, 12)

            if let err = errorMessage {
                Text(err).font(.caption).foregroundColor(.red).transition(.opacity).padding(.bottom, 4)
            }

            Spacer()

            TextField("", text: $pinText)
                .keyboardType(.numberPad)
                .focused($pinFocused)
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .padding(.bottom, 48)
        }
        .contentShape(Rectangle())
        .onTapGesture { pinFocused = true }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pinFocused = true }
        }
        .onChange(of: step) { _, _ in
            pinText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pinFocused = true }
        }
        .onChange(of: pinText) { _, newValue in
            let filtered = String(newValue.filter(\.isNumber).prefix(pinLength))
            if filtered != newValue { pinText = filtered
                return
            }
            if filtered.count == pinLength {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { advance() }
            }
        }
    }

    private func advance() {
        switch step {
        case .enter:
            firstPIN = pinText
            pinText = ""
            errorMessage = nil
            withAnimation { step = .confirm }
        case .confirm:
            if pinText == firstPIN {
                let pin = pinText
                do {
                    try authenticationManager.setPIN(pin, confirmPin: pin)
                    onComplete()
                } catch {
                    errorMessage = String(localized: "Couldn't save your PIN. Please try again.")
                    shake()
                    pinText = ""
                    firstPIN = ""
                    withAnimation { step = .enter }
                }
            } else {
                errorMessage = String(localized: "PINs don't match")
                shake()
                pinText = ""
                firstPIN = ""
                withAnimation { step = .enter }
            }
        }
    }

    private func shake() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.default) { shakeOffset = -10 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.default) { shakeOffset = 6 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.default) { shakeOffset = 0 } }
    }
}

#Preview { PINSetupView(authenticationManager: AuthenticationManager(), onComplete: {}) }
