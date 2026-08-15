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
                Section {
                    LabeledContent("Service") {
                        TextField("Issuer", text: $viewModel.issuer).multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                    LabeledContent("Account") {
                        TextField("Name", text: $viewModel.name).multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                    LabeledContent("Group") {
                        TextField("Optional group label", text: $viewModel.groupName).multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                    Toggle(isOn: $viewModel.isFavorite) {
                        Label("Favorite", systemImage: viewModel.isFavorite ? "star.fill" : "star")
                            .foregroundColor(viewModel.isFavorite ? .yellow : .primary)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                } header: {
                    Text("Account").textCase(.uppercase)
                }

                Section {
                    LabeledContent("Type") {
                        Text(viewModel.tokenTypeDisplayName).foregroundColor(.secondary)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                    Picker("Algorithm", selection: $viewModel.algorithm) {
                        ForEach(Algorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                    Picker("Digits", selection: $viewModel.digits) {
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }
                    .listRowBackground(Constants.Colors.background)
                    .listRowSeparator(.visible)
                    if viewModel.originalToken.type == .totp {
                        LabeledContent("Period") {
                            TextField("30", text: $viewModel.period).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    } else {
                        LabeledContent("Counter") {
                            TextField("0", text: $viewModel.counter).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    }
                } header: {
                    Text("Settings").textCase(.uppercase)
                }

                Section {
                    TextEditor(text: $viewModel.notes)
                        .frame(minHeight: 80)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    Text("Notes are stored securely in the iOS Keychain")
                        .font(.caption2).foregroundColor(.secondary)
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                } header: {
                    Text("Notes").textCase(.uppercase)
                }

                Section {
                    if secretRevealed {
                        Text(viewModel.secretDisplay)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .accessibilityHidden(true)
                            .listRowBackground(Constants.Colors.background)
                            .listRowSeparator(.visible)
                        Button {
                            secretRevealed = false
                        } label: {
                            Label("Hide secret key", systemImage: "eye.slash")
                        }
                        .foregroundColor(.secondary)
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                    } else {
                        Button {
                            showRevealSheet = true
                        } label: {
                            Label("Reveal secret key", systemImage: "eye")
                        }
                        .listRowBackground(Constants.Colors.background)
                        .listRowSeparator(.visible)
                        Text("Your PIN is required to view the secret key")
                            .font(.caption2).foregroundColor(.secondary)
                            .listRowBackground(Constants.Colors.background)
                            .listRowSeparator(.visible)
                    }
                } header: {
                    Text("Secret key").textCase(.uppercase)
                }

                if let err = viewModel.errorMessage {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                            .listRowBackground(Constants.Colors.background)
                            .listRowSeparator(.visible)
                    }
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
            .alert("Duplicate token", isPresented: Binding(
                get: { viewModel.pendingDuplicateAdd != nil },
                set: {
                    if !$0 {
                        viewModel.cancelPendingDuplicateSave()
                    }
                }
            )) {
                Button("Cancel", role: .cancel) { viewModel.cancelPendingDuplicateSave() }
                Button("Save Anyway") { confirmDuplicateSave() }
            } message: {
                if let name = viewModel.pendingDuplicateAdd?.existingName {
                    Text("This matches the secret already saved as \(name). Save it anyway?")
                } else {
                    Text("This token's secret is already in your vault. Save it anyway?")
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

    private func confirmDuplicateSave() {
        Task {
            let success = await viewModel.confirmPendingDuplicateSave()
            if success {
                await MainActor.run {
                    onSave()
                    dismiss()
                }
            }
        }
    }
}
