import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ExportDocument

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json, .plainText]

    var data: Data?

    init(data: Data?) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data ?? Data())
    }
}

// MARK: - TokenTransferView

struct TokenTransferView: View {
    @Bindable var viewModel: ExportImportViewModel
    @State private var showPlaintextConfirm = false

    var body: some View {
        Form {
            exportSection
            notesSection
        }
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.background)
        .navigationTitle("Export (backup)")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $viewModel.showExportPicker,
            document: ExportDocument(data: viewModel.exportData),
            contentType: .json,
            defaultFilename: viewModel.exportFilename.isEmpty ? viewModel.defaultExportFilename : viewModel
                .exportFilename
        ) { viewModel.handleExportResult($0) }
        .navigationDestination(isPresented: $viewModel.showEncryptedExportSheet) {
            EncryptedExportPasswordSheet(exportImportManager: viewModel.exportImportManager) { data in
                viewModel.exportFilename = viewModel.defaultEncryptedExportFilename
                viewModel.exportData = data
                viewModel.showEncryptedExportSheet = false
                viewModel.showExportPicker = true
            }
        }
        .navigationDestination(isPresented: $viewModel.showMigrationQR) {
            MigrationQRExportView(exportImportManager: viewModel.exportImportManager)
        }
        .alert("Export successful", isPresented: $viewModel.showExportSuccess) {
            Button("OK", role: .cancel) { viewModel.exportData = nil }
        } message: {
            Text("Your tokens have been saved to a JSON file")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                showPlaintextConfirm = true
            } label: {
                if viewModel.isExporting {
                    HStack { ProgressView().scaleEffect(0.8)
                        Text("Exporting…")
                    }
                } else {
                    Label("Export as JSON", systemImage: "doc.text")
                }
            }
            .disabled(viewModel.isExporting || !viewModel.hasTokens)
            .foregroundColor(viewModel.isExporting || !viewModel.hasTokens ? .gray : .blue)
            .listRowBackground(Constants.Colors.rowBackground)
            .alert("Unencrypted export", isPresented: $showPlaintextConfirm) {
                Button("Export", role: .destructive) {
                    viewModel.exportFilename = viewModel.defaultExportFilename
                    viewModel.startJSONExport()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This backup will contain your token secrets in plain text. Store it in a secure location such as an encrypted disk or password manager. Consider using encrypted JSON instead."
                )
            }

            Button {
                viewModel.showEncryptedExportSheet = true
            } label: {
                Label("Export as encrypted JSON", systemImage: "lock.doc")
            }
            .disabled(!viewModel.hasTokens)
            .foregroundColor(viewModel.hasTokens ? .blue : .gray)
            .listRowBackground(Constants.Colors.rowBackground)

            Button {
                viewModel.showMigrationQR = true
            } label: {
                Label("Export as QR code", systemImage: "qrcode")
            }
            .disabled(!viewModel.hasTokens)
            .foregroundColor(viewModel.hasTokens ? .blue : .gray)
            .listRowBackground(Constants.Colors.rowBackground)

            if let err = viewModel.exportError {
                Text(err).font(.caption).foregroundColor(.red)
            }

            if viewModel.unreadableTokenCount > 0 {
                Text(
                    "Some tokens couldn't be read and won't be included in this backup (\(viewModel.unreadableTokenCount))."
                )
                .font(.caption).foregroundColor(.orange)
                .listRowBackground(Constants.Colors.rowBackground)
            }
        } header: {
            Text("Export").textCase(.uppercase)
        } footer: {
            if !viewModel.hasTokens {
                Text("Add some tokens first before exporting a backup")
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            noteRow(
                icon: "lock.open.fill",
                color: .orange,
                title: "Plaintext JSON is unencrypted",
                detail: "Store in a secure location such as an encrypted disk or password manager"
            )
            .listRowBackground(Constants.Colors.rowBackground)
            noteRow(
                icon: "lock.fill",
                color: .green,
                title: "Encrypted JSON is recommended",
                detail: "AES-256-GCM with PBKDF2. Password is required to export — keep it safe."
            )
            .listRowBackground(Constants.Colors.rowBackground)
            noteRow(
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                title: "QR code export uses Google Authenticator format",
                detail: "otpauth-migration:// — compatible with Google Authenticator, Aegis, 2FAS, Raivo..."
            )
            .listRowBackground(Constants.Colors.rowBackground)
        } header: { Text("Notes").textCase(.uppercase) }
    }

    private func noteRow(
        icon: String,
        color: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Migration QR Export View

struct MigrationQRExportView: View {
    let exportImportManager: ExportImportManager

    @State private var qrImages: [UIImage] = []
    @State private var currentPage = 0
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var excludedCount = 0
    @State private var imagePendingShare: UIImage?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Generating QR codes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Cannot export",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                qrCarousel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Colors.background)
        .navigationTitle("Export as QR code")
        .navigationBarTitleDisplayMode(.inline)
        .task { await generateMigrationQRs() }
        .confirmingSecretShare($imagePendingShare)
    }

    private var qrCarousel: some View {
        VStack(spacing: 0) {
            if qrImages.count > 1 {
                Text("QR code \(currentPage + 1) of \(qrImages.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 16)
            }

            TabView(selection: $currentPage) {
                ForEach(Array(qrImages.enumerated()), id: \.offset) { index, img in
                    VStack(spacing: 20) {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 280)
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button {
                            imagePendingShare = img
                        } label: {
                            Label(
                                "Share QR code",
                                systemImage: "square.and.arrow.up"
                            )
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: qrImages.count > 1 ? .always : .never))

            Text("Scan this QR code with any compatible app")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, excludedCount > 0 ? 8 : 24)

            if excludedCount > 0 {
                Text(excludedNote)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
    }

    private var excludedNote: String {
        String(
            localized: "Tokens with a time period other than 30 seconds aren't included (\(excludedCount)). Use JSON export for them."
        )
    }

    @MainActor
    private func generateMigrationQRs() async {
        let allTokens = exportImportManager.tokenStore.tokens
        guard !allTokens.isEmpty else {
            errorMessage = String(localized: "Nothing to export")
            isLoading = false
            return
        }
        let tokens = allTokens.filter { $0.type == .hotp || $0.period == 30 }
        excludedCount = allTokens.count - tokens.count
        guard !tokens.isEmpty else {
            errorMessage = excludedNote
            isLoading = false
            return
        }

        let batchSize = 10
        let batches = stride(from: 0, to: tokens.count, by: batchSize).map {
            Array(tokens[$0 ..< min($0 + batchSize, tokens.count)])
        }

        let batchId = Int32.random(in: 0 ... Int32.max)
        var images: [UIImage] = []

        for (index, batch) in batches.enumerated() {
            let payload = buildMigrationPayload(
                tokens: batch,
                batchIndex: index,
                batchSize: batches.count,
                batchId: batchId
            )
            let b64 = payload.base64EncodedString()
            let urlEncoded = b64
                .replacingOccurrences(of: "+", with: "%2B")
                .replacingOccurrences(of: "/", with: "%2F")
                .replacingOccurrences(of: "=", with: "%3D")
            let uriString = "otpauth-migration://offline?data=\(urlEncoded)"
            guard let img = QRCodeGenerator.generateQRCode(from: uriString, correctionLevel: "M") else {
                errorMessage =
                    String(localized: "QR codes couldn't be created for all tokens. Use JSON export instead.")
                isLoading = false
                return
            }
            images.append(img)
        }

        qrImages = images
        isLoading = false
    }

    // MARK: - Minimal protobuf encoder for Google Authenticator Migration format

    private func buildMigrationPayload(tokens: [Token], batchIndex: Int, batchSize: Int, batchId: Int32) -> Data {
        var data = Data()
        for token in tokens {
            var params = Data()
            appendBytes(&params, fieldNumber: 1, value: token.secret)
            appendBytes(&params, fieldNumber: 2, value: Data(token.name.utf8))
            if let issuer = token.issuer, !issuer.isEmpty {
                appendBytes(&params, fieldNumber: 3, value: Data(issuer.utf8))
            }
            let algoVal: UInt64 = token.algorithm == .sha256 ? 2 : token.algorithm == .sha512 ? 3 : 1
            appendVarint(&params, fieldNumber: 4, value: algoVal)
            appendVarint(&params, fieldNumber: 5, value: token.digits == 8 ? 2 : 1)
            appendVarint(&params, fieldNumber: 6, value: token.type == .hotp ? 1 : 2)
            if token.type == .hotp, let counter = token.counter {
                appendVarint(&params, fieldNumber: 7, value: counter)
            }
            appendBytes(&data, fieldNumber: 1, value: params)
        }
        appendVarint(&data, fieldNumber: 2, value: 1)
        appendVarint(&data, fieldNumber: 3, value: UInt64(batchSize))
        appendVarint(&data, fieldNumber: 4, value: UInt64(batchIndex))
        appendVarint(&data, fieldNumber: 5, value: UInt64(bitPattern: Int64(batchId)))
        return data
    }

    private func appendVarint(_ data: inout Data, fieldNumber: Int, value: UInt64) {
        encodeVarint(&data, value: UInt64(fieldNumber << 3))
        encodeVarint(&data, value: value)
    }

    private func appendBytes(_ data: inout Data, fieldNumber: Int, value: Data) {
        encodeVarint(&data, value: UInt64((fieldNumber << 3) | 2))
        encodeVarint(&data, value: UInt64(value.count))
        data.append(value)
    }

    private func encodeVarint(_ data: inout Data, value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while v != 0
    }
}

// MARK: - Encrypted Export Password Sheet

struct EncryptedExportPasswordSheet: View {
    let exportImportManager: ExportImportManager
    let onComplete: (Data) -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isExporting = false
    @State private var errorMessage: String? = nil

    private var passwordsMatch: Bool {
        password == confirmPassword
    }

    private var canExport: Bool {
        password.count >= 8 && passwordsMatch && !isExporting
    }

    var body: some View {
        Form {
            Section {
                SecureField("Password", text: $password)
                    .listRowBackground(Constants.Colors.rowBackground)
                SecureField("Confirm", text: $confirmPassword)
                    .listRowBackground(Constants.Colors.rowBackground)
                if !password.isEmpty, !confirmPassword.isEmpty, !passwordsMatch {
                    Text("Passwords don't match").font(.caption).foregroundColor(.red)
                        .listRowBackground(Constants.Colors.rowBackground)
                }
                if let err = errorMessage {
                    Text(err).font(.caption).foregroundColor(.red)
                        .listRowBackground(Constants.Colors.rowBackground)
                }
            } header: {
                Text("Set password").textCase(.uppercase)
            } footer: {
                Text(
                    "Your tokens will be encrypted with AES-256-GCM. You'll need this password to import the backup."
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.background)
        .navigationTitle("Export as encrypted JSON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isExporting {
                    ProgressView().accessibilityLabel("Encrypting…")
                } else {
                    Button("Export") { doExport() }.disabled(!canExport)
                }
            }
        }
    }

    private func doExport() {
        isExporting = true
        errorMessage = nil
        let password = password
        Task {
            do {
                let plaintext = try exportImportManager.exportVault()
                let data = try await Task.detached(priority: .userInitiated) {
                    try EncryptionService.encrypt(plaintext, password: password)
                }.value
                onComplete(data)
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Encrypted Import Password Sheet

struct EncryptedImportPasswordSheet: View {
    let exportImportManager: ExportImportManager
    let encryptedData: Data
    let onComplete: (ExportImportManager.ImportResult?) -> Void

    @State private var password = ""
    @State private var isDecrypting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        Form {
            Section {
                SecureField("Password", text: $password)
                    .listRowBackground(Constants.Colors.rowBackground)
                if let err = errorMessage {
                    Text(err).font(.caption).foregroundColor(.red)
                        .listRowBackground(Constants.Colors.rowBackground)
                }
            } header: {
                Text("Enter the password for this backup").textCase(.uppercase)
            } footer: {
                Text("The backup is encrypted with AES-256-GCM. Enter the password used when it was exported.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.background)
        .navigationTitle("Encrypted JSON import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDecrypting {
                    ProgressView().accessibilityLabel("Decrypting…")
                } else {
                    Button("Import") { doImport() }.disabled(password.isEmpty)
                }
            }
        }
    }

    private func doImport() {
        isDecrypting = true
        errorMessage = nil
        let encrypted = encryptedData
        let enteredPassword = password
        Task {
            do {
                let plaintext = try await Task.detached(priority: .userInitiated) {
                    try EncryptionService.decrypt(encrypted, password: enteredPassword)
                }.value
                let result = try exportImportManager.parseTokens(from: plaintext)
                onComplete(result)
            } catch ExportImportError.wrongPassword {
                isDecrypting = false
                errorMessage = ExportImportError.wrongPassword.localizedDescription
                password = ""
            } catch {
                isDecrypting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TokenTransferView(viewModel: ExportImportViewModel(tokenStore: TokenStore(), settings: AppSettings()))
    }
}
