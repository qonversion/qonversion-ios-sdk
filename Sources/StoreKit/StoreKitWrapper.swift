//
//  StoreKitWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

/// Accounts for transactions the local StoreKit verification rejected. They
/// are never reported to the backend — an unverified JWS proves nothing — but
/// the drop must not be silent either.
protocol UnverifiedTransactionReporter: AnyObject, Sendable {

    func reportUnverifiedTransaction(_ error: Error?, source: String)
}

// @unchecked: stateless mapper, weak delegate, lock-guarded promo task.
final class StoreKitWrapper: StoreKitWrapperInterface, @unchecked Sendable {

    #if !os(watchOS) && !os(tvOS) && !os(visionOS)
    // Weak: the delegate (facade) holds the wrapper itself.
    weak var delegate: StoreKitWrapperDelegate?
    #endif

    private let mapper: StoreKitMapperInterface

    /// Where a rejected transaction is accounted for, so every observation
    /// path reports through one counter. Weak: the reporter (the facade) owns
    /// the wrapper.
    weak var unverifiedReporter: UnverifiedTransactionReporter?

    #if !os(watchOS) && !os(tvOS) && !os(visionOS)
    private let promoSubscriptionLock = NSLock()
    private var promoIntentsTask: Task<Void, Never>?
    #endif

    init(mapper: StoreKitMapperInterface) {
        self.mapper = mapper
    }

    func products(for ids: [String]) async throws -> [StoreKit.Product] {
        let products: [StoreKit.Product] = try await Product.products(for: ids)

        return products
    }

    func currentEntitlements() async -> [Qonversion.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.currentEntitlements)
    }

    func restore() async throws -> [Qonversion.Transaction] {
        return try await Self.restoreTransactions(
            localTransactions: { await self.fetchTransactions(for: StoreKit.Transaction.all) },
            sync: { try await AppStore.sync() }
        )
    }

    /// AppStore.sync() shows an App Store authentication prompt by design, so
    /// it runs only when the device itself has nothing to restore.
    static func restoreTransactions(
        localTransactions: () async -> [Qonversion.Transaction],
        sync: () async throws -> Void
    ) async throws -> [Qonversion.Transaction] {
        let local: [Qonversion.Transaction] = await localTransactions()
        guard local.isEmpty else { return local }

        do {
            try await sync()
        } catch {
            // Raw StoreKit errors must never reach the integrator.
            throw StoreKitPurchaseOutcome.storeError(error, fallbackType: .restoreFailed)
        }

        return await localTransactions()
    }

    /// Extracted so the mapping stays testable without a real StoreKit product.
    static func storeOptions(for options: Qonversion.PurchaseOptions) -> Set<Product.PurchaseOption> {
        var purchaseOptions: Set<Product.PurchaseOption> = []
        if options.quantity > 1 {
            purchaseOptions.insert(.quantity(options.quantity))
        }
        if let appAccountToken = options.appAccountToken {
            purchaseOptions.insert(.appAccountToken(appAccountToken))
        }
        if let promoOffer = options.promoOffer {
            purchaseOptions.insert(.promotionalOffer(
                offerID: promoOffer.offerId,
                keyID: promoOffer.keyId,
                nonce: promoOffer.nonce,
                signature: promoOffer.signature,
                timestamp: promoOffer.timestamp
            ))
        }
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            // Win-back offers are applied only when the caller passes an offer
            // that came from the store itself.
            if let winBackOffer = options.winBackOffer?.originalOffer {
                purchaseOptions.insert(.winBackOffer(winBackOffer))
            }
        }

        return purchaseOptions
    }

    func fetchAll() async -> [Qonversion.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.all)
    }

    func fetchUnfinished() async -> [Qonversion.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.unfinished)
    }

    func finish(_ transaction: Qonversion.Transaction) async {
        guard let storeKitTransaction: StoreKit.Transaction = transaction.storeKitTransaction else { return }

        await storeKitTransaction.finish()
    }

    func purchase(product: Product, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction {
        let purchaseOptions: Set<Product.PurchaseOption> = Self.storeOptions(for: options)

        let result: Product.PurchaseResult
        do {
            result = try await buy(product, with: purchaseOptions)
        } catch let error as QonversionError {
            // Re-mapping would bury it under a generic .purchaseFailed.
            throw error
        } catch {
            // Raw StoreKit errors must never reach the integrator.
            throw StoreKitPurchaseOutcome.failed(error).qonversionError() ?? QonversionError(type: .purchaseFailed, error: error)
        }

        let outcome: StoreKitPurchaseOutcome
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                outcome = .success(mapper.map(transaction, jws: verificationResult.jwsRepresentation))
            case .unverified(_, let verificationError):
                outcome = .unverified(verificationError)
            }
        case .userCancelled:
            outcome = .userCancelled
        case .pending:
            outcome = .pending
        @unknown default:
            outcome = .failed(nil)
        }

        if case .success(let transaction) = outcome {
            return transaction
        }
        throw outcome.qonversionError() ?? QonversionError(type: .purchaseFailed)
    }

    // visionOS requires the purchase sheet to be confirmed in a scene only the
    // host can name. Main-actor isolated rather than lock-guarded, so the
    // UIKit reference never crosses an isolation boundary.
    #if os(visionOS)
    /// Held weakly: the SDK must never keep a discarded scene alive.
    @MainActor
    private weak var purchaseConfirmationScene: UIScene?

    @MainActor
    func setPurchaseConfirmationScene(_ scene: UIScene?) {
        purchaseConfirmationScene = scene
    }

    @MainActor
    private func buy(_ product: Product, with options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        guard let scene: UIScene = purchaseConfirmationScene else {
            throw QonversionError(type: .purchaseSceneMissing)
        }

        return try await product.purchase(confirmIn: scene, options: options)
    }
    #else
    private func buy(_ product: Product, with options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        return try await product.purchase(options: options)
    }
    #endif

    /// Verified out-of-band transaction updates. Never finishes a transaction
    /// itself — the lifecycle belongs to the consumer.
    func transactionUpdates() -> AsyncStream<Qonversion.Transaction> {
        return AsyncStream { continuation in
            let task: Task<Void, Never> = Task {
                for await update in StoreKit.Transaction.updates {
                    switch update {
                    case .verified(let transaction):
                        continuation.yield(self.mapper.map(transaction, jws: update.jwsRepresentation))
                    case .unverified(_, let error):
                        self.unverifiedReporter?.reportUnverifiedTransaction(error, source: "the transaction updates listener")
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func storefrontUpdates() -> AsyncStream<Void> {
        return AsyncStream { continuation in
            let task: Task<Void, Never> = Task {
                for await _ in Storefront.updates {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    #if !os(watchOS) && !os(tvOS) && !os(visionOS)
    @available(iOS 16.4, macOS 14.4, *)
    func subscribeToPromoPurchases() {
        promoSubscriptionLock.lock()
        defer { promoSubscriptionLock.unlock() }
        guard promoIntentsTask == nil else { return }

        promoIntentsTask = Task { [weak self] in
            for await purchaseIntent in PurchaseIntent.intents {
                guard let self, !Task.isCancelled else { return }
                self.delegate?.promoPurchaseIntent(product: purchaseIntent.product)
            }
        }
    }

    func unsubscribeFromPromoPurchases() {
        promoSubscriptionLock.lock()
        defer { promoSubscriptionLock.unlock() }
        promoIntentsTask?.cancel()
        promoIntentsTask = nil
    }
    #endif

    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, visionOS 1.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }
    #endif

    private func fetchTransactions(for type: StoreKit.Transaction.Transactions) async -> [Qonversion.Transaction] {
        var transasctions: [Qonversion.Transaction] = []
        for await transaction in type {
            switch transaction {
            case .verified(let verifiedTransaction):
                transasctions.append(mapper.map(verifiedTransaction, jws: transaction.jwsRepresentation))
            case .unverified(_, let error):
                unverifiedReporter?.reportUnverifiedTransaction(error, source: "a store transactions query")
            }
        }

        return transasctions
    }
}
