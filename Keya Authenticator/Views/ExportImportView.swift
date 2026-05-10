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
    @Environment(\.dismiss) private var dismiss
    @State private var showPlaintextConfirm = false
    @State private var showNoTokensAlert = false

    var body: some View {
        Form {
            exportSection
            notesSection
        }
        .scrollContentBackground(.hidden)
        .background(Constants.Colors.background)
        .navigationTitle("Export (Backup)")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $viewModel.showExportPicker,
            document: ExportDocument(data: viewModel.exportData),
            contentType: .json,
            defaultFilename: viewModel.exportFilename.isEmpty ? viewModel.defaultExportFilename : viewModel
                .exportFilename
        ) { viewModel.handleExportResult($0) }
        .sheet(isPresented: $viewModel.showEncryptedExportSheet) {
            EncryptedExportPasswordSheet(exportImportManager: viewModel.exportImportManager) { data in
                viewModel.exportFilename = viewModel.defaultEncryptedExportFilename
                viewModel.exportData = data
                viewModel.showEncryptedExportSheet = false
                viewModel.showExportPicker = true
            }
        }
        .sheet(isPresented: $viewModel.showMigrationQR) {
            MigrationQRExportView(exportImportManager: viewModel.exportImportManager)
        }
        .alert("Export successful", isPresented: $viewModel.showExportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your tokens have been saved to a JSON file")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                guard viewModel.hasTokens else { showNoTokensAlert = true
                    return
                }
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
            .disabled(viewModel.isExporting)
            .foregroundColor(viewModel.isExporting ? .gray : .blue)
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
                guard viewModel.hasTokens else { showNoTokensAlert = true
                    return
                }
                viewModel.showEncryptedExportSheet = true
            } label: {
                Label("Export as encrypted JSON", systemImage: "lock.doc")
            }
            .foregroundColor(.blue)

            Button {
                guard viewModel.hasTokens else { showNoTokensAlert = true
                    return
                }
                viewModel.showMigrationQR = true
            } label: {
                Label("Export as QR code", systemImage: "qrcode")
            }
            .foregroundColor(.blue)
            .alert("Nothing to export", isPresented: $showNoTokensAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Add some tokens first before exporting a backup")
            }

            if let err = viewModel.exportError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        } header: {
            Text("Export")
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
            noteRow(
                icon: "lock.fill",
                color: .green,
                title: "Encrypted JSON is recommended",
                detail: "AES-256-GCM with PBKDF2. Password is required to export — keep it safe."
            )
            noteRow(
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                title: "QR code export uses Google Authenticator format",
                detail: "otpauth-migration:// — compatible with Google Authenticator, Aegis, 2FAS, Raivo..."
            )
        } header: { Text("Notes") }
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
    @Environment(\.dismiss) private var dismiss

    @State private var qrImages: [UIImage] = []
    @State private var currentPage = 0
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Export as QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await generateMigrationQRs() }
        }
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

                        ShareLink(
                            item: Image(uiImage: img),
                            preview: SharePreview("Keya Authenticator QR code \(index + 1)", image: Image(uiImage: img))
                        ) {
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
                .padding(.bottom, 24)
        }
    }

    @MainActor
    private func generateMigrationQRs() async {
        let tokens = exportImportManager.tokenStore.tokens
        guard !tokens.isEmpty else {
            errorMessage = "No tokens to export"
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
            if let img = QRCodeGenerator.generateQRCode(from: uriString, correctionLevel: "M") {
                images.append(img)
            }
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
            if v != 0 { byte |= 0x80 }
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
    @Environment(\.dismiss) private var dismiss

    private var passwordsMatch: Bool {
        password == confirmPassword
    }

    private var canExport: Bool {
        password.count >= 6 && passwordsMatch && !isExporting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                    SecureField("Confirm", text: $confirmPassword)
                    if !password.isEmpty, !confirmPassword.isEmpty, !passwordsMatch {
                        Text("Passwords don't match").font(.caption).foregroundColor(.red)
                    }
                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                } header: {
                    Text("Set password")
                } footer: {
                    Text(
                        "Your tokens will be encrypted with AES-256-GCM. You'll need this password to import the backup."
                    )
                    .font(.caption2)
                }

                Section {
                    Button {
                        doExport()
                    } label: {
                        if isExporting {
                            HStack { ProgressView().scaleEffect(0.8)
                                Text("Encrypting…")
                            }
                        } else {
                            Text("Export")
                        }
                    }
                    .disabled(!canExport)
                    .foregroundColor(canExport ? .blue : .gray)

                    Button("Cancel", role: .cancel) { dismiss() }
                        .foregroundColor(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Constants.Colors.background)
            .navigationTitle("Export as encrypted JSON")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func doExport() {
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let data = try exportImportManager.exportVaultEncrypted(password: password)
                await MainActor.run { onComplete(data) }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                } header: {
                    Text("Enter the password for this backup")
                } footer: {
                    Text("The backup is encrypted with AES-256-GCM. Enter the password used when it was exported.")
                        .font(.caption2)
                }

                Section {
                    Button {
                        doImport()
                    } label: {
                        if isDecrypting {
                            HStack { ProgressView().scaleEffect(0.8)
                                Text("Decrypting…")
                            }
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(password.isEmpty || isDecrypting)
                    .foregroundColor(password.isEmpty || isDecrypting ? .gray : .blue)

                    Button("Cancel", role: .cancel) {
                        onComplete(nil)
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Constants.Colors.background)
            .navigationTitle("Encrypted JSON import")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func doImport() {
        isDecrypting = true
        errorMessage = nil
        Task {
            do {
                let result = try exportImportManager.parseEncryptedTokens(from: encryptedData, password: password)
                await MainActor.run { onComplete(result)
                    dismiss()
                }
            } catch ExportImportError.wrongPassword {
                await MainActor.run {
                    isDecrypting = false
                    errorMessage = "Incorrect password — try again."
                    password = ""
                }
            } catch {
                await MainActor.run {
                    isDecrypting = false
                    errorMessage = error.localizedDescription
                }
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
