import SwiftUI

struct QRExportView: View {
    @Bindable var viewModel: QRExportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 4) {
                        if let issuer = viewModel.tokenIssuer, !issuer.isEmpty {
                            Text(issuer)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text(viewModel.tokenName)
                            .font(.headline)
                    }
                    .padding(.top, 8)

                    if let img = viewModel.qrImage {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                            )
                    } else {
                        ProgressView()
                            .frame(width: 240, height: 240)
                    }

                    if !viewModel.otpauthURI.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("otpauth:// URI")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(viewModel.otpauthURI)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 24)
                    }

                    if let img = viewModel.qrImage {
                        ShareLink(
                            item: Image(uiImage: img),
                            preview: SharePreview("QR code - \(viewModel.displayName)", image: Image(uiImage: img))
                        ) {
                            Label("Share QR code", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 24)
                    }

                    Text("Scan this QR code with any compatible app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.vertical, 16)
            }
            .background(Constants.Colors.background)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    QRExportView(viewModel: QRExportViewModel(token: Token(
        name: "test@example.com",
        issuer: "GitHub",
        secret: Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0xDE, 0xAD, 0xBE, 0xEF]),
        algorithm: .sha1, digits: 6, type: .totp, period: 30
    )))
}
