//
//  StoreKitWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

// @unchecked: the mapper is stateless; the delegate is weak; the promo
// subscription task is lock-guarded.
final class StoreKitWrapper: StoreKitWrapperInterface, @unchecked Sendable {

    #if !os(watchOS)
    // Weak: the delegate (facade) holds the wrapper itself.
    weak var delegate: StoreKitWrapperDelegate?
    #endif

    private let mapper: StoreKitMapperInterface

    #if !os(watchOS)
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

        try await sync()

        return await localTransactions()
    }

    /// The store options a purchase call carries. Extracted so the mapping
    /// stays testable without a real StoreKit product.
    static func storeOptions(for options: Qonversion.PurchaseOptions) -> Set<Product.PurchaseOption> {
        var purchaseOptions: Set<Product.PurchaseOption> = []
        if options.quantity > 1 {
            purchaseOptions.insert(.quantity(options.quantity))
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
        #if !os(visionOS)
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, *) {
            // Win-back offers are applied only when the caller passes an offer
            // that came from the store itself.
            if let winBackOffer = options.winBackOffer?.originalOffer {
                purchaseOptions.insert(.winBackOffer(winBackOffer))
            }
        }
        #endif

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
            result = try await product.purchase(options: purchaseOptions)
        } catch {
            // Raw StoreKit errors must never reach the integrator: a
            // `catch let error as QonversionError` has to cover every failure.
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

    /// A long-lived stream of verified out-of-band transaction updates.
    /// The stream never finishes transactions itself — the transaction
    /// lifecycle is owned by the consumer (and, in Analytics mode, by the
    /// host app).
    func transactionUpdates() -> AsyncStream<Qonversion.Transaction> {
        return AsyncStream { continuation in
            let task: Task<Void, Never> = Task {
                for await update in StoreKit.Transaction.updates {
                    if case .verified(let transaction) = update {
                        continuation.yield(self.mapper.map(transaction, jws: update.jwsRepresentation))
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

    #if !os(watchOS)
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
            default:
                break
            }
        }

        return transasctions
    }
}
