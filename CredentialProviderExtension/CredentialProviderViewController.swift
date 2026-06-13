import AuthenticationServices
import Foundation
import LocalAuthentication
import Security
import UIKit

// MARK: - Constants

private let keychainService = "ee.exx.KeyaAuthenticator"

private let reservedAccounts = Token.reservedKeychainAccounts

// MARK: - CredentialProviderViewController

final class CredentialProviderViewController: ASCredentialProviderViewController {

    // MARK: Properties

    private var allTokens: [Token] = []
    private var displayedTokens: [Token] = []
    private var tableView: UITableView?

    // MARK: - ASCredentialProviderViewController overrides

    override func prepareOneTimeCodeCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        authenticateThenPresent(serviceIdentifiers: serviceIdentifiers)
    }

    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: any ASCredentialRequest
    ) {
        extensionContext.cancelRequest(
            withError: ASExtensionError(.userInteractionRequired)
        )
    }

    override func prepareInterfaceToProvideCredential(
        for credentialRequest: any ASCredentialRequest
    ) {
        if credentialRequest is ASOneTimeCodeCredentialRequest {
            authenticateThenDeliver(request: credentialRequest)
        } else {
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
