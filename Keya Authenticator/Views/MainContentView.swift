import SwiftUI
import UniformTypeIdentifiers

struct MainContentView: View {
    @ScaledMetric(relativeTo: .caption) private var toastIconSize: CGFloat = 13
    @ScaledMetric(relativeTo: .largeTitle) private var emptySearchIconSize: CGFloat = 32
    @Bindable var viewModel: MainContentViewModel
    var onResetRequested: (() throws -> Void)?

    @Environment(\.editMode) private var editMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingPINAuthForExport = false
    @State private var tokenPendingPINAuth: Token? = nil
    @State private var tokenAwaitingDeletePIN: Token?
    @State private var tokenVerifiedForDelete: Token?

    // MARK: - Sheet view models

    @State private var addTokenViewModel: AddTokenViewModel?
    @State private var editTokenViewModel: EditTokenViewModel?
    @State private var exportImportViewModel: ExportImportViewModel?
    @State private var qrExportViewModel: QRExportViewModel?

    var body: some View {
        NavigationStack {
            tokenList
                .scrollContentBackground(.hidden)
                .background(Constants.Colors.background)
                .navigationTitle("app.name")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $viewModel.searchText, prompt: "Search tokens")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { viewModel.showingSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .accessibilityLabel("Settings")
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        Button {
                            viewModel.captureSnapshotBeforeAdd()
                            viewModel.showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                        }
                        .accessibilityLabel("Add")
                    }
                }
                .onChange(of: viewModel.searchText) { _, q in
                    if !q.isEmpty, editMode?.wrappedValue.isEditing == true {
                        editMode?.wrappedValue = .inactive
                    }
                }
                .onChange(of: viewModel.showingAddSheet) { _, isShowing in
                    if isShowing, addTokenViewModel == nil {
                        addTokenViewModel = AddTokenViewModel(
                            tokenStore: viewModel.tokenStore,
                            settings: viewModel.settings,
                            prefillURI: viewModel.pendingOTPAuthURI
                        )
                        viewModel.pendingOTPAuthURI = nil
                    } else if !isShowing {
                        addTokenViewModel = nil
                    }
                }
                .sheet(isPresented: $viewModel.showingAddSheet, onDismiss: { viewModel.addSheetDismissed() }, content: {
                    if let addTokenViewModel {
                        AddTokenView(
                            viewModel: addTokenViewModel,
                            onTokenAdded: { viewModel.trackNewTokens() }
                        )
                    }
                })
                .onChange(of: viewModel.selectedTokenForEdit) { _, token in
                    editTokenViewModel = token.map {
                        EditTokenViewModel(tokenStore: viewModel.tokenStore, settings: viewModel.settings, token: $0)
                    }
                }
                .sheet(item: $viewModel.selectedTokenForEdit) { _ in
                    if let editTokenViewModel {
                        EditTokenView(
                            viewModel: editTokenViewModel,
                            authenticationManager: viewModel.authenticationManager
                        ) { viewModel.selectedTokenForEdit = nil }
                    }
                }
                .onChange(of: viewModel.selectedTokenForQR) { _, token in
                    qrExportViewModel = token.map { QRExportViewModel(token: $0) }
                }
                .sheet(item: $viewModel.selectedTokenForQR) { _ in
                    if let qrExportViewModel {
                        QRExportView(viewModel: qrExportViewModel)
                    }
                }
                .alert("Back up your tokens", isPresented: $viewModel.showBackupNudge) {
                    Button("Export") { viewModel.handleBackupExport() }
                    Button("Later", role: .cancel) { viewModel.handleBackupLater() }
                } message: {
                    Text("Losing this app without a backup means losing access to your accounts.")
                }
                .onChange(of: viewModel.showExportSheet) { _, isShowing in
                    if isShowing, exportImportViewModel == nil {
                        exportImportViewModel = ExportImportViewModel(
                            tokenStore: viewModel.tokenStore,
                            settings: viewModel.settings
                        )
                    } else if !isShowing {
                        exportImportViewModel = nil
                    }
                }
                .sheet(isPresented: $viewModel.showExportSheet) {
                    if let exportImportViewModel {
                        NavigationStack {
                            TokenTransferView(viewModel: exportImportViewModel)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        CloseButton { viewModel.showExportSheet = false }
                                    }
                                }
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showingSettings) {
                    SettingsView(
                        tokenStore: viewModel.tokenStore,
                        authenticationManager: viewModel.authenticationManager,
                        settings: viewModel.settings,
                        onResetRequested: onResetRequested
                    )
                }
                .sheet(isPresented: $viewModel.showingPINAuthForBackupExport) {
                    PINAuthSheet(authenticationManager: viewModel.authenticationManager) {
                        viewModel.showExportSheet = true
                        viewModel.showingPINAuthForBackupExport = false
                    } onCancel: {
                        viewModel.showingPINAuthForBackupExport = false
                    }
                }
                .sheet(isPresented: $showingPINAuthForExport) {
                    PINAuthSheet(authenticationManager: viewModel.authenticationManager) {
                        if let token = tokenPendingPINAuth {
                            viewModel.selectedTokenForQR = token
                        }
                        showingPINAuthForExport = false
                        tokenPendingPINAuth = nil
                    } onCancel: {
                        showingPINAuthForExport = false
                        tokenPendingPINAuth = nil
                    }
                }
                .sheet(item: $tokenAwaitingDeletePIN, onDismiss: {
                    viewModel.tokenPendingDelete = tokenVerifiedForDelete
                    tokenVerifiedForDelete = nil
                }, content: { token in
                    PINAuthSheet(authenticationManager: viewModel.authenticationManager) {
                        tokenVerifiedForDelete = token
                        tokenAwaitingDeletePIN = nil
                    } onCancel: {
                        tokenAwaitingDeletePIN = nil
                    }
                })
                .onAppear {
                    viewModel.loadTokens()
                    viewModel.settings.recordActiveDay(on: Date())
                }
                .destructiveActionSheet(
                    isPresented: Binding(
                        get: { viewModel.tokenPendingDelete != nil },
                        set: {
                            if !$0 {
                                viewModel.tokenPendingDelete = nil
                            }
                        }
                    ),
                    title: String(localized: "Delete token?"),
                    message: deleteTokenMessage,
                    actionTitle: String(localized: "Delete")
                ) {
                    if let token = viewModel.tokenPendingDelete {
                        viewModel.deleteToken(token)
                    }
                }
                .alert("Something went wrong", isPresented: Binding(
                    get: { viewModel.operationErrorMessage != nil },
                    set: {
                        if !$0 {
                            viewModel.operationErrorMessage = nil
                        }
                    }
                )) {
                    Button("OK", role: .cancel) { viewModel.operationErrorMessage = nil }
                } message: {
                    Text(viewModel.operationErrorMessage ?? "")
                }
        }
        .overlay(alignment: .top) {
            if viewModel.showCopyToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: toastIconSize))
                    Text("Copied").font(.caption.weight(.medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Constants.Colors.confirmationGreen)
                .clipShape(Capsule())
                .padding(.top, 12)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showCopyToast)
    }

    private var deleteTokenMessage: String {
        guard let token = viewModel.tokenPendingDelete else {
            return String(localized: "This will permanently delete this token. This cannot be undone.")
        }
        let label = [token.issuer, token.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
        return String(localized: "This will permanently delete \(label). This cannot be undone.")
    }

    // MARK: - Token list

    private var tokenList: some View {
        List {
            if viewModel.tokenStore.tokens.isEmpty {
                Section {
                    emptyState.frame(maxWidth: .infinity)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                let (favs, groups) = viewModel.tokenSections

                if favs.isEmpty, groups.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: emptySearchIconSize, weight: .light))
                                .foregroundColor(.secondary)
                            Text("No results for \"\(viewModel.searchText)\"")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Text("Check the spelling or try a different search.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    if !favs.isEmpty {
                        Section {
                            ForEach(favs) { token in tokenRow(token) }
                                .onMove { from, to in
                                    viewModel.moveTokens(fromOffsets: from, toOffset: to, in: favs)
                                }
                        } header: {
                            sectionLabel("Favorites")
                        }
                    }

                    let hasNamedGroups = groups.contains(where: { $0.title != nil })
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.tokens) { token in tokenRow(token) }
                                .onMove { from, to in
                                    viewModel.moveTokens(fromOffsets: from, toOffset: to, in: group.tokens)
                                }
                        } header: {
                            if let title = group.title {
                                sectionLabel(verbatim: title)
                            } else if !favs.isEmpty || hasNamedGroups {
                                sectionLabel("Other")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func sectionLabel(verbatim title: String) -> some View {
        Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func tokenRow(_ token: Token) -> some View {
        TokenRowView(
            token: token,
            settings: viewModel.settings,
            onEdit: { viewModel.selectedTokenForEdit = token },
            onExportQR: { requestPINForExport(token) },
            onCounterIncrement: { viewModel.incrementCounter(for: token) },
            onFavoriteToggle: { viewModel.toggleFavorite(token) },
            onCopy: { viewModel.copyCodeToClipboard(from: token) },
            isNew: viewModel.isTokenNew(token)
        )
        .listRowBackground(Constants.Colors.rowBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { requestDelete(token) }
                label: { Label("Delete", systemImage: "trash") }.tint(.red)
            Button { requestPINForExport(token) }
                label: { Label("QR code", systemImage: "qrcode") }.tint(.purple)
            Button { viewModel.selectedTokenForEdit = token }
                label: { Label("Edit token", systemImage: "pencil") }.tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { viewModel.copyCodeToClipboard(from: token) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }.tint(.blue)
            Button { viewModel.toggleFavorite(token) } label: {
                Label(
                    token.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: token.isFavorite ? "star.slash" : "star.fill"
                )
            }.tint(.yellow)
        }
        .contextMenu {
            Button { viewModel.copyCodeToClipboard(from: token) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button { viewModel.toggleFavorite(token) } label: {
                Label(
                    token.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: token.isFavorite ? "star.slash" : "star"
                )
            }
            Divider()
            Button { viewModel.selectedTokenForEdit = token } label: {
                Label("Edit token", systemImage: "pencil")
            }
            Button { requestPINForExport(token) } label: {
                Label("QR code", systemImage: "qrcode")
            }
            Divider()
            Button(role: .destructive) { requestDelete(token) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                emptyStateIcon
                VStack(spacing: 8) {
                    Text("No tokens yet").font(.title3.weight(.medium))
                    Text("Tap the + button to add your first\ntwo-factor authentication token")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding()
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 180)
    }

    @ViewBuilder
    private var emptyStateIcon: some View {
        let base = Image("AppIconImage")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .grayscale(1.0)
        if colorScheme == .dark {
            base.colorInvert().opacity(0.35)
        } else {
            base.opacity(0.25)
        }
    }

    // MARK: - PIN Auth triggers

    private func requestPINForExport(_ token: Token) {
        tokenPendingPINAuth = token
        showingPINAuthForExport = true
    }

    private func requestDelete(_ token: Token) {
        if viewModel.settings.isAuthenticationEnabled, KeychainManager.isPINSet() {
            tokenAwaitingDeletePIN = token
        } else {
            viewModel.tokenPendingDelete = token
        }
    }
}

#Preview {
    MainContentView(
        viewModel: MainContentViewModel(
            tokenStore: TokenStore(),
            authenticationManager: AuthenticationManager(),
            settings: AppSettings()
        )
    )
}
