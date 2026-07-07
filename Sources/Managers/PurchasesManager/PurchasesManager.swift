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
    private let logger: LoggerWrapper

    private let reportsGate = TransactionReportsGate()

    init(
        purchasesService: PurchasesServiceInterface,
        storeKitFacade: StoreKitFacadeInterface,
        userManager: UserManagerInterface,
        entitlementsManager: EntitlementsManagerInterface,
        userIdProvider: UserIdProvider,
        launchModeProvider: LaunchModeProvider,
        logger: LoggerWrapper
    ) {
        self.purchasesService = purchasesService
        self.storeKitFacade = storeKitFacade
        self.userManager = userManager
        self.entitlementsManager = entitlementsManager
        self.userIdProvider = userIdProvider
        self.launchModeProvider = launchModeProvider
        self.logger = logger
    }

    @discardableResult
    func purchase(_ product: Qonversion.Product, options: Qonversion.PurchaseOptions?) async throws -> Qonversion.PurchaseResult {
        // The backend user must exist before the purchase is reported.
        _ = try await userManager.obtainUser()

        let transaction = try await storeKitFacade.purchase(storeId: product.storeId, options: options ?? Qonversion.PurchaseOptions())

        do {
            try await purchasesService.send(transaction, userId: userIdProvider.getUserId(), options: options)
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
                try await purchasesService.send(transaction, userId: userIdProvider.getUserId())
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

    func startObservingTransactions() {
        storeKitFacade.startObservingTransactionUpdates()
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
                try await purchasesService.send(transaction, userId: userIdProvider.getUserId())
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
    }

    func transactionUpdated(_ transaction: Qonversion.Transaction) {
        // Out-of-band update (renewal, refund, Ask to Buy approval, another
        // device): report it, never finish it — the transaction lifecycle is
        // owned by the host app (Analytics mode) or by the purchase flow.
        Task { [weak self] in
            guard let self else { return }
            // Transactions without a store id (degraded SK1 mapping) cannot be
            // deduplicated and are reported unconditionally.
            if let id = transaction.id {
                guard await self.reportsGate.tryTake(id) else { return }
            }
            do {
                _ = try await self.userManager.obtainUser()
                try await self.purchasesService.send(transaction, userId: self.userIdProvider.getUserId())
            } catch {
                if let id = transaction.id {
                    await self.reportsGate.release(id)
                }
                self.logger.error("Failed to report an observed transaction: " + error.message)
            }
        }
    }
}
