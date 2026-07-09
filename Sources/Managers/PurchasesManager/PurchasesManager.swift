//
//  PurchasesManager.swift
//  Qonversion
//

import Foundation
import StoreKit

final class PurchasesManager: PurchasesManagerInterface {

    private let purchasesService: PurchasesServiceInterface
    private let storeKitFacade: StoreKitFacadeInterface
    private let userManager: UserManagerInterface
    private let entitlementsManager: EntitlementsManagerInterface
    private let userIdProvider: UserIdProvider
    private let launchModeProvider: LaunchModeProvider
    private let purchaseAssociationsStorage: PurchaseAssociationsStorage
    private let logger: LoggerWrapper

    private let reportsGate = TransactionReportsGate()

    /// Emits fresh entitlements after the SDK processes an observed
    /// transaction in subscription-management mode.
    private let entitlementsUpdatesMulticast = AsyncMulticast<[String: Qonversion.Entitlement]>()

    /// Emits App Store promoted-purchase intents. Buffered until the first
    /// subscriber — an intent arriving at app start must not be lost.
    private let promoIntentsMulticast = AsyncMulticast<Qonversion.PromoPurchaseIntent>(buffersWhenNoSubscribers: true)

    func entitlementsUpdates() -> AsyncStream<[String: Qonversion.Entitlement]> {
        return entitlementsUpdatesMulticast.stream()
    }

    func promoPurchaseIntents() -> AsyncStream<Qonversion.PromoPurchaseIntent> {
        return promoIntentsMulticast.stream()
    }

    init(
        purchasesService: PurchasesServiceInterface,
        storeKitFacade: StoreKitFacadeInterface,
        userManager: UserManagerInterface,
        entitlementsManager: EntitlementsManagerInterface,
        userIdProvider: UserIdProvider,
        launchModeProvider: LaunchModeProvider,
        purchaseAssociationsStorage: PurchaseAssociationsStorage,
        logger: LoggerWrapper
    ) {
        self.purchasesService = purchasesService
        self.storeKitFacade = storeKitFacade
        self.userManager = userManager
        self.entitlementsManager = entitlementsManager
        self.userIdProvider = userIdProvider
        self.launchModeProvider = launchModeProvider
        self.purchaseAssociationsStorage = purchaseAssociationsStorage
        self.logger = logger
    }

    @discardableResult
    func purchase(_ product: Qonversion.Product, options: Qonversion.PurchaseOptions?) async throws -> Qonversion.PurchaseResult {
        // The backend user must exist before the purchase is reported.
        _ = try await userManager.obtainUser()

        // Persisted for the whole purchase lifecycle: a report happening
        // after a relaunch (unfinished sweep, Ask to Buy approval) must still
        // carry the paywall context of THIS call.
        if options?.contextKeys?.isEmpty == false || options?.screenUid != nil {
            purchaseAssociationsStorage.store(
                PurchaseAssociations(contextKeys: options?.contextKeys, screenUid: options?.screenUid),
                for: product.storeId
            )
        }

        let transaction: Qonversion.Transaction
        do {
            transaction = try await storeKitFacade.purchase(storeId: product.storeId, options: options ?? Qonversion.PurchaseOptions())
        } catch {
            // A pending purchase (Ask to Buy) arrives later via the listener
            // and must keep its associations; any other failure means no
            // transaction will ever match them.
            if (error as? QonversionError)?.type != .purchasePending {
                purchaseAssociationsStorage.remove(for: product.storeId)
            }
            throw error
        }

        do {
            try await purchasesService.send(transaction, userId: userIdProvider.getUserId(), options: options)
            purchaseAssociationsStorage.remove(for: product.storeId)
        } catch {
            // Production fault tolerance: when the backend is unreachable the
            // purchase still succeeds with locally calculated entitlements.
            // The transaction stays unfinished so it can be re-reported later.
            if error.allowsLocalEntitlementsFallback {
                let entitlements = await entitlementsManager.localFallbackEntitlements(for: [transaction])
                return Qonversion.PurchaseResult(transaction: transaction, entitlements: entitlements)
            }
            throw QonversionError(type: .purchaseReportingFailed, message: nil, error: error)
        }

        // Mark as reported, so the updates listener never re-reports it.
        if let id = transaction.id {
            _ = await reportsGate.tryTake(id)
        }

        // Finish strictly after the backend confirmed the purchase.
        await storeKitFacade.finish(transaction)

        // A reported purchase must not fail because of the entitlements fetch.
        let entitlements: [String: Qonversion.Entitlement]
        if let fetched = try? await entitlementsManager.entitlements() {
            entitlements = fetched
        } else {
            entitlements = await entitlementsManager.localFallbackEntitlements(for: [transaction])
        }

        return Qonversion.PurchaseResult(transaction: transaction, entitlements: entitlements)
    }

    @discardableResult
    func restore() async throws -> [String: Qonversion.Entitlement] {
        _ = try await userManager.obtainUser()

        let restored = try await storeKitFacade.restore()
        // Production rule: only the latest transaction per product participates.
        let latest = EntitlementsCalculator.latestTransactionsPerProduct(restored)

        do {
            for transaction in latest {
                // Skip transactions already reported this session (sweep,
                // listener or purchase); the failed report releases the id.
                if let id = transaction.id {
                    guard await reportsGate.tryTake(id) else { continue }
                }
                do {
                    try await purchasesService.send(transaction, userId: userIdProvider.getUserId())
                } catch {
                    if let id = transaction.id {
                        await reportsGate.release(id)
                    }
                    throw error
                }
            }
        } catch {
            if error.allowsLocalEntitlementsFallback {
                return await entitlementsManager.localFallbackEntitlements(for: latest)
            }
            throw QonversionError(type: .restoreFailed, message: nil, error: error)
        }

        if let fetched = try? await entitlementsManager.entitlements() {
            return fetched
        }
        return await entitlementsManager.localFallbackEntitlements(for: latest)
    }

    func promotionalOffer(for product: Qonversion.Product, discountId: String) async throws -> Qonversion.PromotionalOffer {
        _ = try await userManager.obtainUser()

        return try await purchasesService.promotionalOffer(userId: userIdProvider.getUserId(), offerId: discountId, productStoreId: product.storeId)
    }

    /// Associations of the original SDK-initiated purchase of this product,
    /// if the report has not delivered them yet.
    private func reportOptions(for transaction: Qonversion.Transaction) -> Qonversion.PurchaseOptions? {
        guard let associations = purchaseAssociationsStorage.associations(for: transaction.productId) else { return nil }

        return Qonversion.PurchaseOptions(contextKeys: associations.contextKeys, screenUid: associations.screenUid)
    }

    func startObservingTransactions() {
        storeKitFacade.startObservingTransactionUpdates()
    }

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    func handle(purchasedTransactions: [VerificationResult<StoreKit.Transaction>]) async {
        let transactions = purchasedTransactions.compactMap { storeKitFacade.map($0) }

        await handle(transactions: transactions)
    }

    func handle(transactions: [Qonversion.Transaction]) async {
        guard !transactions.isEmpty else { return }

        do {
            _ = try await userManager.obtainUser()
        } catch {
            logger.error("Skipping handed transactions: no backend user: " + error.message)
            return
        }

        // The host app made these purchases and owns their lifecycle — the
        // SDK only tracks them, so no transaction is ever finished here.
        for transaction in transactions {
            if let id = transaction.id {
                guard await reportsGate.tryTake(id) else { continue }
            }
            do {
                try await purchasesService.send(transaction, userId: userIdProvider.getUserId())
            } catch {
                if let id = transaction.id {
                    await reportsGate.release(id)
                }
                logger.error("Failed to report a handed transaction: " + error.message)
            }
        }
    }

    func processUnfinishedTransactions() async {
        // In Analytics mode the host app owns the transaction lifecycle.
        guard launchModeProvider.launchMode == .subscriptionManagement else { return }

        let transactions = await storeKitFacade.unfinishedTransactions()
        guard !transactions.isEmpty else { return }

        do {
            _ = try await userManager.obtainUser()
        } catch {
            logger.error("Skipping unfinished transactions: no backend user: " + error.message)
            return
        }

        for transaction in transactions {
            if let id = transaction.id {
                guard await reportsGate.tryTake(id) else { continue }
            }
            do {
                try await purchasesService.send(transaction, userId: userIdProvider.getUserId(), options: reportOptions(for: transaction))
                purchaseAssociationsStorage.remove(for: transaction.productId)
                await storeKitFacade.finish(transaction)
            } catch {
                if let id = transaction.id {
                    await reportsGate.release(id)
                }
                logger.error("Failed to re-report an unfinished transaction: " + error.message)
            }
        }
    }
}

// MARK: - StoreKitFacadeDelegate

extension PurchasesManager: StoreKitFacadeDelegate {

    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) {
        emitPromoPurchaseIntent(storeProductId: product.id)
    }

    /// Hands the promoted-purchase intent to the host through the stream; its
    /// purchase() runs the regular purchase flow. The report keys off the
    /// transaction's store product id, so no Qonversion product mapping is
    /// required.
    func emitPromoPurchaseIntent(storeProductId: String) {
        let intent = Qonversion.PromoPurchaseIntent(productId: storeProductId) { [weak self] options in
            guard let self else { throw QonversionError.initializationError() }

            return try await self.purchase(Qonversion.Product(qonversionId: storeProductId, storeId: storeProductId, offeringId: nil), options: options)
        }

        promoIntentsMulticast.yield(intent)
    }

    func transactionUpdated(_ transaction: Qonversion.Transaction) {
        // Out-of-band update (renewal, refund, Ask to Buy approval, another
        // device). In Analytics mode it is only reported — the host app owns
        // the lifecycle. In subscription-management mode the SDK owns it:
        // finish after the backend ack and emit fresh entitlements to the
        // update streams.
        Task { [weak self] in
            guard let self else { return }
            // Transactions without a store id (degraded SK1 mapping) cannot be
            // deduplicated and are reported unconditionally.
            if let id = transaction.id {
                guard await self.reportsGate.tryTake(id) else { return }
            }
            do {
                _ = try await self.userManager.obtainUser()
                try await self.purchasesService.send(transaction, userId: self.userIdProvider.getUserId(), options: self.reportOptions(for: transaction))
                self.purchaseAssociationsStorage.remove(for: transaction.productId)
            } catch {
                if let id = transaction.id {
                    await self.reportsGate.release(id)
                }
                self.logger.error("Failed to report an observed transaction: " + error.message)
                return
            }

            guard self.launchModeProvider.launchMode == .subscriptionManagement else { return }

            await self.storeKitFacade.finish(transaction)

            let entitlements: [String: Qonversion.Entitlement]
            if let fetched = try? await self.entitlementsManager.entitlements() {
                entitlements = fetched
            } else {
                entitlements = await self.entitlementsManager.localFallbackEntitlements(for: [transaction])
            }
            self.entitlementsUpdatesMulticast.yield(entitlements)
        }
    }
}
