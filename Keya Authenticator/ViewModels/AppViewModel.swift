import Foundation
import SwiftUI

@Observable
final class AppCoordinator {
    // MARK: - Dependencies

    private let tokenStore: TokenStore
    private let authenticationManager: AuthenticationManager
    private let settings: AppSettings

    // MARK: - Published Properties

    var appState: AppState = .loading
    var showPrivacyOverlay = false
    private var pendingIncomingURL: URL?

    // MARK: - Child ViewModels

    var mainContentViewModel: MainContentViewModel

    // MARK: - App State

    enum AppState {
        case loading
        case pinSetup
        case appUnlock
        case main
    }

    // MARK: - Initialization

    init(tokenStore: TokenStore, authenticationManager: AuthenticationManager, settings: AppSettings) {
        self.tokenStore = tokenStore
        self.authenticationManager = authenticationManager
        self.settings = settings
        mainContentViewModel = MainContentViewModel(
            tokenStore: tokenStore,
            authenticationManager: authenticationManager,
            settings: settings
        )
    }

    // MARK: - App Lifecycle

    func determineInitialState() {
        if !KeychainManager.isPINSet() {
            appState = .pinSetup
        } else if settings.isAuthenticationEnabled {
            checkGracePeriodAndLock()
            appState = .appUnlock
        } else {
            do { try tokenStore.load() } catch {}
            appState = .main
            processPendingURL()
        }
    }

    func handleAppBackground() {
        let timestampSaved = KeychainManager.saveBackgroundTimestamp(Date())
        ClipboardManager.shared.clearClipboard()

        if settings.isAuthenticationEnabled, settings.lockGracePeriod == 0 || !timestampSaved {
            performLock()
        }

        showPrivacyOverlay = true
    }

    func handleAppBecameActive() {
        checkGracePeriodAndLock()

        withAnimation(.easeInOut(duration: 0.25)) {
            showPrivacyOverlay = false
        }
    }

    private func checkGracePeriodAndLock() {
        defer { KeychainManager.deleteBackgroundTimestamp() }
        guard let bg = KeychainManager.loadBackgroundTimestamp() else { return }
        let elapsed = Date().timeIntervalSince(bg)
        if settings.isAuthenticationEnabled, elapsed >= TimeInterval(settings.lockGracePeriod) {
            performLock()
        }
    }

    private func performLock() {
        guard settings.isAuthenticationEnabled, appState == .main else { return }
        tokenStore.clear()
        withAnimation {
            appState = .appUnlock
        }
    }

    // MARK: - State Transitions

    func completePINSetup() {
        settings.isAuthenticationEnabled = true
        do { try tokenStore.load() } catch {}
        withAnimation { appState = .main }
        processPendingURL()
    }

    func completeUnlock() {
        do { try tokenStore.load() } catch {}
        withAnimation { appState = .main }
        processPendingURL()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "otpauth" else { return }
        if appState == .main {
            mainContentViewModel.openAddSheet(prefillURI: url.absoluteString)
        } else {
            pendingIncomingURL = url
        }
    }

    private func processPendingURL() {
        guard let url = pendingIncomingURL else { return }
        pendingIncomingURL = nil
        mainContentViewModel.openAddSheet(prefillURI: url.absoluteString)
    }

    func requestReset() {
        withAnimation { appState = .pinSetup }
    }

    // MARK: - Reset Everything

    func resetEverything() {
        authenticationManager.performReset(tokenStore: tokenStore, settings: settings)
        withAnimation { appState = .pinSetup }
    }
}
