import AuthenticationServices
import Foundation
import LocalAuthentication
import Security
import UIKit

// MARK: - Constants

private let keychainService = Constants.keychainService

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
            guard let tokens = self.loadTokens() else {
                self.extensionContext.cancelRequest(withError: ASExtensionError(.failed))
                return
            }
            self.allTokens = tokens
            let matches = self.matching(self.allTokens, for: serviceIdentifiers)
            self.displayedTokens = matches.isEmpty ? self.allTokens : matches
            self.showTableView()
        }
    }

    private func authenticateThenDeliver(request: any ASCredentialRequest) {
        evaluate { [weak self] granted in
            guard let self, granted else { return }
            guard let tokens = self.loadTokens() else {
                self.extensionContext.cancelRequest(withError: ASExtensionError(.failed))
                return
            }
            self.allTokens = tokens

            let serviceID = request.credentialIdentity.serviceIdentifier
            let candidates = self.matching(self.allTokens, for: [serviceID])

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

    private func loadTokens() -> [Token]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let tokens = items.compactMap { item -> Token? in
            guard
                let account = item[kSecAttrAccount as String] as? String,
                !reservedAccounts.contains(account),
                let data = item[kSecValueData as String] as? Data
            else { return nil }
            return try? decoder.decode(Token.self, from: data)
        }
        .filter { $0.type == .totp }

        var bestByContent: [String: Token] = [:]
        for token in tokens {
            if let existing = bestByContent[token.contentKey],
               existing.updatedAt >= token.updatedAt {
                continue
            }
            bestByContent[token.contentKey] = token
        }
        return Array(bestByContent.values).sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Filtering

    private func matching(
        _ tokens: [Token],
        for identifiers: [ASCredentialServiceIdentifier]
    ) -> [Token] {
        let keywords = identifiers.compactMap { id -> String? in
            let host = id.type == .URL ? URL(string: id.identifier)?.host : id.identifier
            return host.map { BrandKeyword.extract(fromHost: $0) }
        }
        return tokens.filter { token in
            keywords.contains { BrandKeyword.matches(issuer: token.issuer, name: token.name, keyword: $0) }
        }
    }

    // MARK: - UI

    private func showTableView() {
        guard !displayedTokens.isEmpty else {
            extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
            return
        }
        let tv = UITableView(frame: .zero, style: .plain)
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "TokenCell")

        let list = UIViewController()
        list.view = tv
        list.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
            }
        )
        let navigation = UINavigationController(rootViewController: list)

        children.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        view.subviews.forEach { $0.removeFromSuperview() }
        addChild(navigation)
        navigation.view.frame = view.bounds
        navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)
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
