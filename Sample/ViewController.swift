//
//  ViewController.swift
//  Sample
//
//  Created by Suren Sarkisyan on 28.02.2024.
//

import UIKit
import Qonversion

class ViewController: UIViewController {

    private let outputTextView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let actions: [(String, () -> Void)] = [
            ("Products", { self.run { try await self.loadProducts() } }),
            ("Entitlements", { self.run { try await self.checkEntitlements() } }),
            ("Purchase first product", { self.run { try await self.purchaseFirstProduct() } }),
            ("Restore", { self.run { try await self.restore() } }),
            ("User info", { self.run { try await self.userInfo() } }),
            ("Identify", { self.run { try await self.identify() } }),
            ("Logout", { self.logout() }),
            ("Set property", { self.setProperty() }),
        ]

        let buttons = actions.map { title, handler in
            var config = UIButton.Configuration.filled()
            config.title = title
            return UIButton(configuration: config, primaryAction: UIAction { _ in handler() })
        }

        let buttonsStack = UIStackView(arrangedSubviews: buttons)
        buttonsStack.axis = .vertical
        buttonsStack.spacing = 8

        outputTextView.isEditable = false
        outputTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputTextView.layer.borderColor = UIColor.separator.cgColor
        outputTextView.layer.borderWidth = 1

        let rootStack = UIStackView(arrangedSubviews: [buttonsStack, outputTextView])
        rootStack.axis = .vertical
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Actions

    private func loadProducts() async throws -> String {
        let products = try await Qonversion.shared.products()
        guard !products.isEmpty else { return "No products configured" }
        return products.map { "\($0.qonversionId): \($0.storeId) \($0.displayPrice ?? "-")" }.joined(separator: "\n")
    }

    private func checkEntitlements() async throws -> String {
        let entitlements = try await Qonversion.shared.checkEntitlements()
        return format(entitlements)
    }

    private func purchaseFirstProduct() async throws -> String {
        let products = try await Qonversion.shared.products()
        guard let product = products.first else { return "No products configured" }

        let result = try await Qonversion.shared.purchase(product)
        return "Purchased \(result.transaction.productId)\n" + format(result.entitlements)
    }

    private func restore() async throws -> String {
        let entitlements = try await Qonversion.shared.restore()
        return format(entitlements)
    }

    private func userInfo() async throws -> String {
        let user = try await Qonversion.shared.userInfo()
        return "id: \(user.id)"
    }

    private func identify() async throws -> String {
        let user = try await Qonversion.shared.identify("sample_external_id")
        return "Identified as \(user.id)"
    }

    private func logout() {
        Qonversion.shared.logout()
        show("Logged out")
    }

    private func setProperty() {
        Qonversion.shared.setUserProperty("sample@qonversion.io", key: .email)
        show("Email property set")
    }

    // MARK: - Helpers

    private func run(_ action: @escaping () async throws -> String) {
        show("Loading...")
        Task {
            do {
                let result = try await action()
                self.show(result.isEmpty ? "<empty>" : result)
            } catch {
                self.show("Error: \(error)")
            }
        }
    }

    private func format(_ entitlements: [String: Qonversion.Entitlement]) -> String {
        guard !entitlements.isEmpty else { return "No entitlements" }
        return entitlements.values
            .map { "\($0.id): active=\($0.active) source=\($0.source.rawValue)" }
            .joined(separator: "\n")
    }

    private func show(_ text: String) {
        DispatchQueue.main.async {
            self.outputTextView.text = text
        }
    }
}
