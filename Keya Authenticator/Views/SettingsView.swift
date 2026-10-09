import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var tokenStore: TokenStore
    @Bindable var authenticationManager: AuthenticationManager
    @Bindable var settings: AppSettings
    var onResetRequested: (() throws -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var showingResetPIN = false
    @State private var showingResetConfirmation = false
    @State private var resetErrorMessage: String?
    @State private var exportImportViewModel: ExportImportViewModel

    init(
        tokenStore: TokenStore,
        authenticationManager: AuthenticationManager,
        settings: AppSettings,
        onResetRequested: (() throws -> Void)? = nil
    ) {
        self.tokenStore = tokenStore
        self.authenticationManager = authenticationManager
        self.settings = settings
        self.onResetRequested = onResetRequested
        _exportImportViewModel = State(initialValue: ExportImportViewModel(tokenStore: tokenStore, settings: settings))
    }

    private var pinGatingEnabled: Bool {
        settings.isAuthenticationEnabled && KeychainManager.isPINSet()
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Security

                Section {
                    NavigationLink {
                        PINGate(authenticationManager: authenticationManager, isRequired: pinGatingEnabled) {
                            AppLockSettingsView(authenticationManager: authenticationManager, settings: settings)
                        }
                    } label: {
                        settingsRow(
                            icon: "lock.fill",
                            iconBg: .blue,
                            title: "App lock",
                            detail: settings.isAuthenticationEnabled ? "On" : "Off"
                        )
                    }
                    .foregroundColor(.primary)
                    .listRowBackground(Constants.Colors.rowBackground)

                    Toggle(isOn: $settings.hideCodesByDefault) {
                        settingsRow(icon: "eye.slash.fill", iconBg: .gray, title: "Hide tokens")
                    }
                    .listRowBackground(Constants.Colors.rowBackground)

                } header: { Text("Security").textCase(.uppercase) }

                // MARK: - Data

                Section {
                    NavigationLink {
                        PINGate(authenticationManager: authenticationManager, isRequired: pinGatingEnabled) {
                            TokenTransferView(viewModel: exportImportViewModel)
                        }
                    } label: {
                        settingsRow(icon: "square.and.arrow.up", iconBg: .green, title: "Export (backup)")
                    }
                    .foregroundColor(.primary)
                    .listRowBackground(Constants.Colors.rowBackground)
                } header: {
                    Text("Data").textCase(.uppercase)
                } footer: {
                    if let date = settings.lastBackupDate {
                        Text("Last export (backup): \(date.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Backup your tokens regularly to avoid losing access to your accounts")
                    }
                }

                // MARK: - Preferences

                Section {
                    Picker(selection: $settings.appTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    } label: {
                        settingsRow(icon: "paintbrush.fill", iconBg: .pink, title: "Theme")
                    }
                    .listRowBackground(Constants.Colors.rowBackground)
                } header: { Text("Preferences").textCase(.uppercase) }

                // MARK: - Support

                Section {
                    NavigationLink {
                        TipJarView()
                    } label: {
                        settingsRow(icon: "heart.fill", iconBg: .white, iconColor: .red, title: "Support development")
                            .foregroundStyle(.white)
                    }
                    .listRowBackground(Color.red)
                } footer: {
                    Text("Free forever. No ads, no subscription. Tips keep the app alive.")
                }

                // MARK: - About

                Section {
                    if let url = Constants.aboutURL {
                        Link(destination: url) {
                            settingsRow(icon: "info.circle.fill", iconBg: .blue, title: "About")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.rowBackground)
                    }
                    if let url = Constants.privacyPolicyURL {
                        Link(destination: url) {
                            settingsRow(icon: "hand.raised.fill", iconBg: .indigo, title: "Privacy policy")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.rowBackground)
                    }
                    if let url = Constants.termsOfServiceURL {
                        Link(destination: url) {
                            settingsRow(icon: "doc.text.fill", iconBg: .gray, title: "Terms of service")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.rowBackground)
                    }
                    if let url = Constants.faqURL {
                        Link(destination: url) {
                            settingsRow(icon: "questionmark.circle.fill", iconBg: .orange, title: "FAQ")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.rowBackground)
                    }
                } header: { Text("We're open-source — learn more").textCase(.uppercase) }

                // MARK: - Danger Zone

                Section {
                    Button(role: .destructive) {
                        if pinGatingEnabled {
                            showingResetPIN = true
                        } else {
                            showingResetConfirmation = true
                        }
                    } label: {
                        settingsRow(icon: "trash.fill", iconBg: .red, title: "Delete all data")
                    }
                    .listRowBackground(Constants.Colors.rowBackground)
                } footer: {
                    Text("This will permanently delete all your tokens and settings. This cannot be undone.")
                }

                // MARK: - Footer

                Section {} footer: {
                    Text(
                        "© \(String(Calendar.current.component(.year, from: Date()))) Keya Authenticator, \(Constants.appVersion) (\(Constants.appBuild)), GPL v3"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Constants.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(settings.appTheme.colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingResetPIN) {
                PINPrompt(authenticationManager: authenticationManager) { showingResetConfirmation = true }
            }
            .destructiveActionSheet(
                isPresented: $showingResetConfirmation,
                title: String(localized: "Delete all data?"),
                message: String(
                    localized: "This will permanently delete all your tokens and settings. This cannot be undone."
                ),
                actionTitle: String(localized: "Delete")
            ) {
                do {
                    try onResetRequested?()
                    dismiss()
                } catch {
                    resetErrorMessage = error.localizedDescription
                }
            }
            .onChange(of: showingResetConfirmation) { _, isShowing in
                if !isShowing {
                    showingResetPIN = false
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { resetErrorMessage != nil },
                set: {
                    if !$0 {
                        resetErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) { resetErrorMessage = nil }
            } message: {
                Text(resetErrorMessage ?? "")
            }
        }
    }

    // MARK: - Row Helper

    private func settingsRow(
        icon: String,
        iconBg: Color,
        iconColor: Color = .white,
        title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconBg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title).font(.body)
            if let detail {
                Spacer()
                Text(detail).font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
    }
}
