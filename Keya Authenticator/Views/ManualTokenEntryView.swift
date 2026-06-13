import PhotosUI
import SwiftUI

// MARK: - Manual Token Entry View

struct ManualTokenEntryView: View {
    @Bindable var viewModel: AddTokenViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showingScanner = false
    @State private var showingGalleryPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil

    @State private var showAdvanced = false

    private var canAdd: Bool {
        !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !viewModel.secret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack { coreContent }
    }

    // MARK: - Core content (shared between embedded and standalone)

    private var coreContent: some View {
        ScrollView {
            manualForm
        }
        .background(Constants.Colors.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerView { result in
                viewModel.processQRScanResult(result)
                showingScanner = false
            }
        }
        .photosPicker(
            isPresented: $showingGalleryPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .onChange(of: selectedPhoto) { _, newItem in
            guard let item = newItem else { return }
            Task { await viewModel.loadGalleryPhotoIntoForm(item)
                selectedPhoto = nil
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
    }

    // MARK: - Manual form

    private var manualForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Service").font(.caption).foregroundColor(.secondary)
                TextField("e.g. AWS, GitHub, Google...", text: $viewModel.issuer)
                    .textContentType(.organizationName)
                    .padding(12)
                    .background(Constants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Account").font(.caption).foregroundColor(.secondary)
                TextField("e.g. you@example.com", text: $viewModel.name)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .padding(12)
                    .background(Constants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Secret key").font(.caption).foregroundColor(.secondary)
                TextField("Base32 encoded key", text: $viewModel.secret)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Constants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(secretBorderColor, lineWidth: 0.5))
                if !viewModel.secret.isEmpty {
                    if viewModel.secret.isValidOTPSecret {
                        Label("Valid secret key", systemImage: "checkmark.circle.fill")
                            .font(.caption2).foregroundColor(.green)
                    } else {
                        Label("Invalid Base32 format", systemImage: "xmark.circle.fill")
                            .font(.caption2).foregroundColor(.red)
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    Text("Advanced options").font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if showAdvanced {
                advancedOptions.transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let err = viewModel.errorMessage {
                Text(err).font(.caption).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { viewModel.createToken() } label: {
                if viewModel.isAddingToken {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                } else {
                    Text("Add").font(.body.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
            }
            .background(canAdd ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(!canAdd || viewModel.isAddingToken)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var secretBorderColor: Color {
        if viewModel.secret.isEmpty { return Color(.separator).opacity(0.3) }
        return viewModel.secret.isValidOTPSecret ? .green.opacity(0.5) : .red.opacity(0.5)
    }

    // MARK: - Advanced options

    private var advancedOptions: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    chipButton("TOTP", selected: viewModel.tokenType == .totp) { viewModel.tokenType = .totp }
                    chipButton("HOTP", selected: viewModel.tokenType == .hotp) { viewModel.tokenType = .hotp }
                }
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Algorithm").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        chipButton("SHA-1", selected: viewModel.algorithm == .sha1) { viewModel.algorithm = .sha1 }
                        chipButton("SHA-256", selected: viewModel.algorithm == .sha256) { viewModel.algorithm = .sha256
                        }
                        chipButton("SHA-512", selected: viewModel.algorithm == .sha512) { viewModel.algorithm = .sha512
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Digits").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        chipButton("6", selected: viewModel.digits == 6) { viewModel.digits = 6 }
                        chipButton("8", selected: viewModel.digits == 8) { viewModel.digits = 8 }
                    }
                }
            }
            if viewModel.tokenType == .totp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Period").font(.caption).foregroundColor(.secondary)
                    TextField("30", text: Binding(
                        get: { String(viewModel.period) },
                        set: { viewModel.period = Int($0) ?? 30 }
                    ))
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Constants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Initial counter").font(.caption).foregroundColor(.secondary)
                    TextField("0", text: Binding(
                        get: { String(viewModel.counter) },
                        set: { viewModel.counter = UInt64($0) ?? 0 }
                    ))
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Constants.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
                }
            }
        }
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? Color.blue.opacity(0.1) : Constants.Colors.background)
                .foregroundColor(selected ? .blue : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.blue.opacity(0.3) : Color(.separator).opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ManualTokenEntryView(
        viewModel: AddTokenViewModel(
            tokenStore: TokenStore(),
            settings: AppSettings()
        )
    )
}
