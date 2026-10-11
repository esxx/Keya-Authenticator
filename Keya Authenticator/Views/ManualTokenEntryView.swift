import SwiftUI

// MARK: - Manual Token Entry View

struct ManualTokenEntryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var chevronSize: CGFloat = 11
    @Bindable var viewModel: AddTokenViewModel
    var onDismissAttempt: () -> Void = {}

    @State private var showAdvanced = false
    @State private var periodText = ""

    private var canAdd: Bool {
        !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !viewModel.secret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        coreContent
    }

    // MARK: - Core content (shared between embedded and standalone)

    private var coreContent: some View {
        ScrollView {
            manualForm
        }
        .background(Constants.Colors.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .background(SwipeDismissAttempt(onAttempt: onDismissAttempt))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isAddingToken {
                    ProgressView()
                } else {
                    Button("Add") { viewModel.createToken() }.disabled(!canAdd)
                }
            }
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
                    .background(Constants.Colors.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Account").font(.caption).foregroundColor(.secondary)
                TextField("e.g. you@example.com", text: $viewModel.name)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .padding(12)
                    .background(Constants.Colors.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Secret key").font(.caption).foregroundColor(.secondary)
                SecureField("Base32 encoded key", text: $viewModel.secret)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Constants.Colors.rowBackground)
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
                        .font(.system(size: chevronSize, weight: .medium))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    Text("Advanced options").font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if showAdvanced {
                advancedOptions.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            if let err = viewModel.errorMessage {
                Text(err).font(.caption).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var secretBorderColor: Color {
        if viewModel.secret.isEmpty {
            return Color(.separator).opacity(0.3)
        }
        return viewModel.secret.isValidOTPSecret ? .green.opacity(0.5) : .red.opacity(0.5)
    }

    // MARK: - Advanced options

    private var advancedOptions: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type").font(.caption).foregroundColor(.secondary)
                Picker("Type", selection: $viewModel.tokenType) {
                    Text(TokenType.totp.displayName).tag(TokenType.totp)
                    Text(TokenType.hotp.displayName).tag(TokenType.hotp)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Algorithm").font(.caption).foregroundColor(.secondary)
                Picker("Algorithm", selection: $viewModel.algorithm) {
                    ForEach(Algorithm.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Digits").font(.caption).foregroundColor(.secondary)
                Picker("Digits", selection: $viewModel.digits) {
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if viewModel.tokenType == .totp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Period").font(.caption).foregroundColor(.secondary)
                    TextField("30", text: $periodText)
                        .keyboardType(.numberPad)
                        .onAppear { periodText = viewModel.period == 30 ? "" : String(viewModel.period) }
                        .onChange(of: periodText) { _, text in
                            viewModel.period = text.isEmpty ? 30 : (Int(text) ?? 0)
                        }
                        .onChange(of: viewModel.period) { _, period in
                            let shown = periodText.isEmpty ? 30 : Int(periodText)
                            if shown != period {
                                periodText = String(period)
                            }
                        }
                        .padding(10)
                        .background(Constants.Colors.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            Color(.separator).opacity(0.3),
                            lineWidth: 0.5
                        ))
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
                    .background(Constants.Colors.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ManualTokenEntryView(
            viewModel: AddTokenViewModel(
                tokenStore: TokenStore(),
                settings: AppSettings()
            )
        )
    }
}
