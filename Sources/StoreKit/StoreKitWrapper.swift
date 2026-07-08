//
//  StoreKitWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.02.2024.
//

import Foundation
import StoreKit

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
final class StoreKitWrapper: StoreKitWrapperInterface {

    // Weak: the delegate (facade) holds the wrapper itself.
    weak var delegate: StoreKitWrapperDelegate?

    private let mapper: StoreKitMapperInterface

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
        try await AppStore.sync()

        return await fetchTransactions(for: StoreKit.Transaction.all)
    }

    func fetchAll() async -> [Qonversion.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.all)
    }

    func fetchUnfinished() async -> [Qonversion.Transaction] {
        return await fetchTransactions(for: StoreKit.Transaction.unfinished)
    }

    func finish(_ transaction: Qonversion.Transaction) async {
        guard let storeKitTransaction = transaction.storeKitTransaction else { return }

        await storeKitTransaction.finish()
    }

    func purchase(product: Product, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction {
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

        let result: Product.PurchaseResult = try await product.purchase(options: purchaseOptions)

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
            let task = Task {
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

    @available(iOS 16.4, macOS 14.4, *)
    func subscribeToPromoPurchases() {
        Task.detached {
            for await purchaseIntent in PurchaseIntent.intents {
                self.delegate?.promoPurchaseIntent(product: purchaseIntent.product)
            }
        }
    }

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
