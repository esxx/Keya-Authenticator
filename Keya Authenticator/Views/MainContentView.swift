import SwiftUI
import UniformTypeIdentifiers

struct MainContentView: View {
    @Bindable var viewModel: MainContentViewModel
    var onResetRequested: (() -> Void)?

    @Environment(\.editMode) private var editMode
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingPINAuthForExport = false
    @State private var tokenPendingPINAuth: Token? = nil

    var body: some View {
        NavigationStack {
            tokenList
                .scrollContentBackground(.hidden)
                .background(Constants.Colors.background)
                .navigationTitle("app.name")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Constants.Colors.background, for: .navigationBar)
                .toolbarBackground(Constants.Colors.background, for: .bottomBar)
                .searchable(text: $viewModel.searchText, prompt: "Search tokens")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { viewModel.showingSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .medium))
                        }
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
                .sheet(isPresented: $viewModel.showingAddSheet) {
                    AddTokenView(
                        viewModel: AddTokenViewModel(
                            tokenStore: viewModel.tokenStore,
                            settings: viewModel.settings,
                            prefillURI: viewModel.pendingOTPAuthURI
                        ),
                        onTokenAdded: { viewModel.trackNewTokens() }
                    )
                    .onAppear { viewModel.pendingOTPAuthURI = nil }
                }
                .sheet(item: $viewModel.selectedTokenForEdit) { token in
                    EditTokenView(
                        viewModel: EditTokenViewModel(
                            tokenStore: viewModel.tokenStore,
                            settings: viewModel.settings,
                            token: token
                        ),
                        authenticationManager: viewModel.authenticationManager
                    ) { viewModel.selectedTokenForEdit = nil }
                }
                .sheet(item: $viewModel.selectedTokenForQR) { token in
                    QRExportView(viewModel: QRExportViewModel(token: token))
                }
                .alert("Back up your tokens", isPresented: $viewModel.showBackupNudge) {
                    Button("Export") { viewModel.handleBackupExport() }
                    Button("Later", role: .cancel) { viewModel.handleBackupLater() }
                } message: {
                    Text("Losing this app without a backup means losing access to your accounts.")
                }
                .sheet(isPresented: $viewModel.showExportSheet) {
                    NavigationStack {
                        TokenTransferView(viewModel: ExportImportViewModel(
                            tokenStore: viewModel.tokenStore,
                            settings: viewModel.settings
                        ))
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
                .onAppear { viewModel.loadTokens() }
                .alert("Delete token?", isPresented: Binding(
                    get: { viewModel.tokenPendingDelete != nil },
                    set: {
                        if !$0 {
                            viewModel.tokenPendingDelete = nil
                        }
                    }
                )) {
                    Button("Cancel", role: .cancel) { viewModel.tokenPendingDelete = nil }
                    Button("Delete", role: .destructive) {
                        if let token = viewModel.tokenPendingDelete {
                            viewModel.deleteToken(token)
                        }
                        viewModel.tokenPendingDelete = nil
                    }
                } message: {
                    if let token = viewModel.tokenPendingDelete {
                        let label = [token.issuer, token.name].compactMap { $0 }.filter { !$0.isEmpty }
                            .joined(separator: " – ")
                        Text("This will permanently delete \(label). This cannot be undone.")
                    } else {
                        Text("This will permanently delete this token. This cannot be undone.")
                    }
                }
                .alert("Something Went Wrong", isPresented: Binding(
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
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                    Text("Copied").font(.caption.weight(.medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color.green)
                .clipShape(Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showCopyToast)
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
                let favs = viewModel.favoriteTokens
                let groups = viewModel.groupedOtherTokens

                if favs.isEmpty, groups.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32, weight: .light))
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
        .listStyle(.plain)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(nil)
    }

    private func sectionLabel(verbatim title: String) -> some View {
        Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(nil)
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
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 1, trailing: 16))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { viewModel.tokenPendingDelete = token }
                label: { Label("Delete", systemImage: "trash") }
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
            .aspectRatio(contentMode: .fit)
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
}

// MARK: - PIN Auth Sheet

struct PINAuthSheet: View {
    let authenticationManager: AuthenticationManager
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var pinText = ""
    @State private var pinError: String? = nil
    @State private var lockoutSecondsRemaining: Int? = nil
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var pinFocused: Bool

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
                            .accessibilityLabel(i < pinText.count ?
                                String(localized: "Digit \(i + 1) entered") :
                                String(localized: "Digit \(i + 1) empty"))
                    }
                }
                .offset(x: shakeOffset)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)

                if let error = pinError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                        .padding(.bottom, 4)
                }

                Spacer()

                TextField("", text: $pinText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($pinFocused)
                    .opacity(0.001)
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
                    .onChange(of: pinText) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(pinLength))
                        if filtered != newValue {
                            pinText = filtered
                            return
                        }
                        if filtered.count == pinLength {
                            verify()
                        }
                    }

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
            shake()
            if let seconds = authenticationManager.pinLockoutSecondsRemaining(), seconds > 0 {
                lockoutSecondsRemaining = seconds
            }
        } catch {
            pinError = "PIN verification failed"
            pinText = ""
            shake()
        }
    }

    private func shake() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.default) { shakeOffset = -10 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.default) { shakeOffset = 6 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.default) { shakeOffset = 0 } }
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
