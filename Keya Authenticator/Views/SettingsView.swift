import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var tokenStore: TokenStore
    @Bindable var authenticationManager: AuthenticationManager
    @Bindable var settings: AppSettings
    var onResetRequested: (() -> Void)?

    @State private var showingResetConfirmation = false
    @State private var showingResetGate = false
    @State private var showingTipJar = false
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToAppLock = false
    @State private var navigateToTransfer = false
    @State private var showingAppLockGate = false
    @State private var showingTransferGate = false

    private var pinGatingEnabled: Bool {
        settings.isAuthenticationEnabled && KeychainManager.isPINSet()
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Security

                Section {
                    Button {
                        if pinGatingEnabled {
                            showingAppLockGate = true
                        } else {
                            navigateToAppLock = true
                        }
                    } label: {
                        HStack {
                            settingsRow(
                                icon: "lock.fill",
                                iconBg: .blue,
                                title: "App lock",
                                detail: settings.isAuthenticationEnabled ? "On" : "Off"
                            )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .foregroundColor(.primary)
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)

                    Toggle(isOn: $settings.hideCodesByDefault) {
                        settingsRow(icon: "eye.slash.fill", iconBg: .gray, title: "Hide tokens")
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)

                } header: { Text("Security").textCase(.uppercase) }

                // MARK: - Data

                Section {
                    Button {
                        if pinGatingEnabled {
                            showingTransferGate = true
                        } else {
                            navigateToTransfer = true
                        }
                    } label: {
                        HStack {
                            settingsRow(icon: "square.and.arrow.up", iconBg: .green, title: "Export (Backup)")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .foregroundColor(.primary)
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
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
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                } header: { Text("Preferences").textCase(.uppercase) }

                // MARK: - Support

                Section {
                    Button { showingTipJar = true } label: {
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
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    }
                    if let url = Constants.privacyPolicyURL {
                        Link(destination: url) {
                            settingsRow(icon: "hand.raised.fill", iconBg: .indigo, title: "Privacy Policy")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    }
                    if let url = Constants.termsOfServiceURL {
                        Link(destination: url) {
                            settingsRow(icon: "doc.text.fill", iconBg: .gray, title: "Terms of Service")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    }
                    if let url = Constants.faqURL {
                        Link(destination: url) {
                            settingsRow(icon: "questionmark.circle.fill", iconBg: .orange, title: "FAQ")
                        }
                        .foregroundColor(.primary)
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    }
                } header: { Text("We're open-source — learn more").textCase(.uppercase) }

                // MARK: - Danger Zone

                Section {
                    Button(role: .destructive) {
                        if pinGatingEnabled {
                            showingResetGate = true
                        } else {
                            showingResetConfirmation = true
                        }
                    } label: {
                        settingsRow(icon: "trash.fill", iconBg: .red, title: "Delete all data")
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                } footer: {
                    Text("This will permanently delete all your tokens and settings. This cannot be undone.")
                        .font(.caption)
                }

                // MARK: - Footer

                Section {} footer: {
                    Text(
                        "© \(String(Calendar.current.component(.year, from: Date()))) Eldar SHAIDULLIN — Keya Authenticator \(Constants.appVersion) (\(Constants.appBuild)) — GPL v3"
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete all data?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    dismiss()
                    onResetRequested?()
                }
            } message: {
                Text("This will permanently delete all your tokens and settings. This cannot be undone.")
            }
            .sheet(isPresented: $navigateToAppLock) {
                NavigationStack {
                    AppLockSettingsView(authenticationManager: authenticationManager, settings: settings)
                }
            }
            .sheet(isPresented: $navigateToTransfer) {
                NavigationStack {
                    TokenTransferView(viewModel: ExportImportViewModel(tokenStore: tokenStore, settings: settings))
                }
            }
            .sheet(isPresented: $showingAppLockGate) {
                PINVerifySheet(authenticationManager: authenticationManager) { verified in
                    showingAppLockGate = false
                    if verified {
                        navigateToAppLock = true
                    }
                }
            }
            .sheet(isPresented: $showingTransferGate) {
                PINVerifySheet(authenticationManager: authenticationManager) { verified in
                    showingTransferGate = false
                    if verified {
                        navigateToTransfer = true
                    }
                }
            }
            .sheet(isPresented: $showingTipJar) {
                TipJarView()
            }
            .sheet(isPresented: $showingResetGate) {
                PINVerifySheet(authenticationManager: authenticationManager) { verified in
                    showingResetGate = false
                    if verified {
                        showingResetConfirmation = true
                    }
                }
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
