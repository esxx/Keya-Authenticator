import SwiftUI

struct EditTokenView: View {
    @Bindable var viewModel: EditTokenViewModel
    let authenticationManager: AuthenticationManager
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var secretRevealed = false
    @State private var showRevealSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Service") {
                        TextField("Issuer", text: $viewModel.issuer).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Account") {
                        TextField("Name", text: $viewModel.name).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Group") {
                        TextField("Optional group label", text: $viewModel.groupName).multilineTextAlignment(.trailing)
                    }
                    Toggle(isOn: $viewModel.isFavorite) {
                        Label("Favorite", systemImage: viewModel.isFavorite ? "star.fill" : "star")
                            .foregroundColor(viewModel.isFavorite ? .yellow : .primary)
                    }
                }

                Section("Settings") {
                    LabeledContent("Type") {
                        Text(viewModel.tokenTypeDisplayName).foregroundColor(.secondary)
                    }
                    Picker("Algorithm", selection: $viewModel.algorithm) {
                        ForEach(Algorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Digits", selection: $viewModel.digits) {
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }
                    if viewModel.originalToken.type == .totp {
                        LabeledContent("Period") {
                            TextField("30", text: $viewModel.period).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        LabeledContent("Counter") {
                            TextField("0", text: $viewModel.counter).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $viewModel.notes)
                        .frame(minHeight: 80)
                        .font(.body)
                    Text("Notes are stored securely in the iOS Keychain")
                        .font(.caption2).foregroundColor(.secondary)
                }

                Section("Secret key") {
                    if secretRevealed {
                        Text(viewModel.secretDisplay)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .accessibilityHidden(true)
                        Button {
                            secretRevealed = false
                        } label: {
                            Label("Hide secret key", systemImage: "eye.slash")
                        }
                        .foregroundColor(.secondary)
                    } else {
                        Button {
                            showRevealSheet = true
                        } label: {
                            Label("Reveal secret key", systemImage: "eye")
                        }
                        Text("Your PIN is required to view the secret key")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                if let err = viewModel.errorMessage {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Constants.Colors.background)
            .task(id: secretRevealed) {
                guard secretRevealed else { return }
                try? await Task.sleep(for: .seconds(30))
                secretRevealed = false
            }
            .navigationTitle("Edit token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.fontWeight(.medium).disabled(viewModel.name.isEmpty || viewModel.isSaving)
                }
            }
            .sheet(isPresented: $showRevealSheet) {
                PINAuthSheet(authenticationManager: authenticationManager) {
                    secretRevealed = true
                    showRevealSheet = false
                } onCancel: {
                    showRevealSheet = false
                }
            }
        }
    }

    private func save() {
        Task {
            let success = await viewModel.saveToken()
            if success {
                await MainActor.run {
                    onSave()
                    dismiss()
                }
            }
        }
    }
}
