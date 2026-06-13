// CredentialProviderViewController.swift
// Keya Authenticator — Credential Provider Extension
//
// This file is the only Swift source unique to the extension target.
// The following existing files must also be added to the extension target's
// "Compile Sources" build phase (Xcode → Target → Build Phases):
//
//   Models/Token.swift
//   Models/Algorithm.swift
//   Models/TokenError.swift
//   Services/OTPGenerator.swift          (also provides Token.generateCode())
//   Utils/Extensions/String+Base32.swift
//   Utils/Extensions/Data+OTP.swift
//
// No other main-app source files are needed.

import AuthenticationServices
import Foundation
import LocalAuthentication
import Security
import UIKit

// MARK: - Constants

// Matches Constants.keychainService in the main app — keep in sync.
private let keychainService = "ee.exx.KeyaAuthenticator"

private let reservedAccounts = Token.reservedKeychainAccounts

// MARK: - CredentialProviderViewController

final class CredentialProviderViewController: ASCredentialProviderViewController {

    // MARK: Properties

    private var allTokens: [Token] = []
    private var displayedTokens: [Token] = []
    private var tableView: UITableView?

    // MARK: - ASCredentialProviderViewController overrides

    /// Called when the user taps the OTP provider button in the keyboard.
    /// Shows the full token list (pre-filtered by service identifier).
    override func prepareOneTimeCodeCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        authenticateThenPresent(serviceIdentifiers: serviceIdentifiers)
    }

    /// Called if the system thinks it can fill a code without UI (e.g. extension
    /// was recently unlocked).  We always require explicit authentication.
    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: any ASCredentialRequest
    ) {
        extensionContext.cancelRequest(
            withError: ASExtensionError(.userInteractionRequired)
        )
    }

    /// Called after `provideCredentialWithoutUserInteraction` returns
    /// `userInteractionRequired`.  Authenticate, then deliver or show list.
    override func prepareInterfaceToProvideCredential(
        for credentialRequest: any ASCredentialRequest
    ) {
        if credentialRequest is ASOneTimeCodeCredentialRequest {
            authenticateThenDeliver(request: credentialRequest)
        } else {
            // Unexpected request type for this extension — show full list.
            authenticateThenPresent(serviceIdentifiers: [])
        }
    }

    // MARK: - Authentication gate

    private func authenticateThenPresent(serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        evaluate { [weak self] granted in
            guard let self, granted else { return }
            self.allTokens = self.loadTokens()
            self.displayedTokens = self.filtered(self.allTokens, for: serviceIdentifiers)
            self.showTableView()
        }
    }

    private func authenticateThenDeliver(request: any ASCredentialRequest) {
        evaluate { [weak self] granted in
            guard let self, granted else { return }
            self.allTokens = self.loadTokens()

            // If we can identify a unique match, fill directly; otherwise show list.
            let serviceID = request.credentialIdentity.serviceIdentifier
            let candidates = self.filtered(self.allTokens, for: [serviceID])

            if candidates.count == 1, let token = candidates.first,
               let code = try? token.generateCode() {
                self.complete(with: code)
            } else {
                self.displayedTokens = candidates.isEmpty ? self.allTokens : candidates
                self.showTableView()
            }
        }
    }

    private func evaluate(completion: @escaping (_ granted: Bool) -> Void) {
        let context = LAContext()
        let reason = String(
            localized: "Authenticate to access your 2FA codes.",
            comment: "Biometric / passcode prompt shown by the AutoFill extension"
        )
        // deviceOwnerAuthentication accepts biometrics OR the device passcode.
        // It deliberately bypasses the app's own PBKDF2 PIN and attempt-lockout —
        // the extension runs in a separate process with no access to app state,
        // and the device passcode is the appropriate trust boundary here.
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] granted, _ in
            DispatchQueue.main.async {
                if granted {
                    completion(true)
                } else {
                    self?.extensionContext.cancelRequest(
                        withError: ASExtensionError(.userCanceled)
                    )
                    completion(false)
                }
            }
        }
    }

    // MARK: - Token loading

    /// Reads token Keychain items directly.  Uses the same Keychain service as the
    /// main app.  Because the extension target declares the same keychain-access-groups
    /// entitlement as the main app, items with that access group are readable here.
    private func loadTokens() -> [Token] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return items.compactMap { item -> Token? in
            guard
                let account = item[kSecAttrAccount as String] as? String,
                !reservedAccounts.contains(account),
                let data = item[kSecValueData as String] as? Data
            else { return nil }
            return try? decoder.decode(Token.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Filtering

    /// Filters tokens whose issuer or name contains any keyword derived from
    /// the service identifiers.  Falls back to the full list when nothing matches.
    private func filtered(
        _ tokens: [Token],
        for identifiers: [ASCredentialServiceIdentifier]
    ) -> [Token] {
        let keywords = identifiers.compactMap { id -> String? in
            if id.type == .URL,
               let host = URL(string: id.identifier)?.host {
                return brandKeyword(from: host)
            }
            return id.identifier.lowercased()
        }
        guard !keywords.isEmpty else { return tokens }

        let matches = tokens.filter { token in
            let haystack = [token.name, token.issuer ?? ""]
                .joined(separator: " ")
                .lowercased()
            return keywords.contains { haystack.contains($0) }
        }
        return matches.isEmpty ? tokens : matches
    }

    /// Extracts the brand name from a host string.
    /// "accounts.google.com" → "google", "github.com" → "github".
    private func brandKeyword(from host: String) -> String {
        let parts = host.lowercased()
            .split(separator: ".")
            .filter { $0 != "www" }
        guard parts.count >= 2 else { return host.lowercased() }
        return String(parts[parts.count - 2])
    }

    // MARK: - UI

    private func showTableView() {
        let tv = UITableView(frame: view.bounds, style: .plain)
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "TokenCell")
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(tv)
        self.tableView = tv
    }

    // MARK: - Code delivery
    // NOTE: HOTP tokens served here do not have their counter incremented back
    // to Keychain. The extension has read-only access; repeated AutoFill of the
    // same HOTP token will return the same code and may desync with the server.

    private func complete(with code: String) {
        let credential = ASOneTimeCodeCredential(code: code)
        extensionContext.completeOneTimeCodeRequest(using: credential, completionHandler: nil)
    }
}

// MARK: - UITableViewDataSource

extension CredentialProviderViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedTokens.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "TokenCell", for: indexPath
        )
        let token = displayedTokens[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = token.issuer ?? token.name
        content.secondaryText = token.issuer != nil ? token.name : nil
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CredentialProviderViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let token = displayedTokens[indexPath.row]
        guard let code = try? token.generateCode() else { return }
        complete(with: code)
    }
}
