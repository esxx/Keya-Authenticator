import Accessibility
import SwiftUI
import UniformTypeIdentifiers

@main
struct AppEntry: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var tokenStore: TokenStore
    @State private var authenticationManager: AuthenticationManager
    @State private var settings: AppSettings
    @State private var appViewModel: AppCoordinator
    @State private var totpClock = TOTPClock()
    @State private var captureGuard = ScreenCaptureGuard()
    @State private var privacyCover = PrivacyCoverWindow()

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
                        onResetRequested: { try appViewModel.resetEverything() }
                    )
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
                privacyCover.setVisible(true, colorScheme: settings.appTheme.colorScheme)
            }
            .onChange(of: appViewModel.showPrivacyOverlay || captureGuard.isCapturing, initial: true) { _, covered in
                privacyCover.setVisible(covered, colorScheme: settings.appTheme.colorScheme)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                appViewModel.handleAppBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                appViewModel.handleAppBecameActive()
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
    @State private var pinFocused = false
    @State private var errorMessage: String? = nil
    @State private var shakeTrigger = 0

    enum Step { case enter, confirm }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("AppIconImage").resizable().scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 20)

            Text("app.name").font(.title2.weight(.medium)).padding(.bottom, 4)

            Text(step == .enter ? String(localized: "Create a 6-digit PIN") : String(localized: "Confirm"))
                .font(.subheadline).foregroundColor(.secondary).padding(.bottom, 32)

            PINEntryView(
                pin: $pinText,
                isFocused: $pinFocused,
                prompt: step == .enter ? String(localized: "Create a 6-digit PIN") : String(localized: "Confirm"),
                errorMessage: errorMessage,
                shakeTrigger: shakeTrigger,
                onComplete: advance
            )

            Spacer()
            Spacer().frame(height: 48)
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
    }

    private func announceUrgently(_ message: String) {
        var text = AttributedString(message)
        text.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(text).post()
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
                    announceUrgently(String(localized: "Couldn't save your PIN. Please try again."))
                    shakeTrigger += 1
                    pinText = ""
                    firstPIN = ""
                    withAnimation { step = .enter }
                }
            } else {
                errorMessage = String(localized: "PINs don't match")
                announceUrgently(String(localized: "PINs don't match"))
                shakeTrigger += 1
                pinText = ""
                firstPIN = ""
                withAnimation { step = .enter }
            }
        }
    }
}

#Preview { PINSetupView(authenticationManager: AuthenticationManager(), onComplete: {}) }
