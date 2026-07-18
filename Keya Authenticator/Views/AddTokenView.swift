import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add Token View (2FAS-style: live scanner + other methods)

struct AddTokenView: View {
    @Bindable var viewModel: AddTokenViewModel
    let onTokenAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showManual = false
    @State private var showGallery = false
    @State private var showFiles = false
    @State private var selectedPhoto: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QRScannerView(onResult: { result in
                    if case let .success(qr) = result {
                        viewModel.handleScannedQR(qr)
                    } else if case let .failure(err) = result {
                        viewModel.errorMessage = err.localizedDescription
                    }
                }, isEmbedded: true)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.33, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Other methods?")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        methodRow(
                            icon: "folder.fill",
                            title: "Import from Files",
                            subtitle: "JSON from Aegis, 2FAS, Raivo, LastPass or Keya Authenticator"
                        ) {
                            showFiles = true
                        }
                        Divider().padding(.leading, 52)
                        methodRow(
                            icon: "photo.on.rectangle.fill",
                            title: "Import from Photo Library",
                            subtitle: "QR code screenshots"
                        ) { showGallery = true }
                        Divider().padding(.leading, 52)
                        methodRow(
                            icon: "keyboard.fill",
                            title: "Enter the secret key manually"
                        ) { showManual = true }
                    }
                    .background(Constants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
            .background(Constants.Colors.background.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
            .navigationTitle("Add tokens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showManual) {
                ManualTokenEntryView(viewModel: viewModel)
            }
            .photosPicker(isPresented: $showGallery, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let item = newItem else { return }
                Task { await viewModel.importGalleryPhoto(item)
                    selectedPhoto = nil
                }
            }
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleFileImport(result)
            }
            .sheet(isPresented: $viewModel.showEncryptedImportSheet) {
                if let encData = viewModel.pendingEncryptedData {
                    EncryptedImportPasswordSheet(
                        exportImportManager: viewModel.importManager,
                        encryptedData: encData
                    ) { result in
                        viewModel.handleEncryptedImportResult(result)
                    }
                }
            }
            .onAppear { viewModel.onTokenAdded = onTokenAdded }
            .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
                if shouldDismiss {
                    viewModel.shouldDismiss = false
                    dismiss()
                }
            }
            .alert("Some tokens skipped", isPresented: .init(
                get: { viewModel.importSkippedCount > 0 },
                set: {
                    if !$0 {
                        viewModel.importSkippedCount = 0
                    }
                }
            )) {
                Button("OK", role: .cancel) { viewModel.importSkippedCount = 0 }
            } message: {
                let n = viewModel.importSkippedCount
                Text(
                    "\(n) token\(n == 1 ? "" : "s") could not be imported because the data was missing or invalid. The remaining tokens were imported successfully."
                )
            }
        }
    }

    // MARK: - Method row

    private func methodRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 52, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddTokenView(
        viewModel: AddTokenViewModel(
            tokenStore: TokenStore(),
            settings: AppSettings()
        ),
        onTokenAdded: {}
    )
}
