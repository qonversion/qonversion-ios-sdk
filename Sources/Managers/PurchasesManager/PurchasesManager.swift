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
    private let userIdProvider: UserIdProvider
    private let logger: LoggerWrapper

    init(
        purchasesService: PurchasesServiceInterface,
        storeKitFacade: StoreKitFacadeInterface,
        userManager: UserManagerInterface,
        userIdProvider: UserIdProvider,
        logger: LoggerWrapper
    ) {
        self.purchasesService = purchasesService
        self.storeKitFacade = storeKitFacade
        self.userManager = userManager
        self.userIdProvider = userIdProvider
        self.logger = logger
    }

    @discardableResult
    func purchase(_ product: Qonversion.Product) async throws -> Qonversion.Transaction {
        // The backend user must exist before the purchase is reported.
        _ = try await userManager.obtainUser()

        let transaction = try await storeKitFacade.purchase(storeId: product.storeId)

        do {
            try await purchasesService.send(transaction, userId: userIdProvider.getUserId())
        } catch {
            // The store purchase went through but the backend doesn't know yet:
            // leave the transaction unfinished so it can be re-reported later.
            throw QonversionError(type: .purchaseReportingFailed, message: nil, error: error)
        }

        // Finish strictly after the backend confirmed the purchase.
        await storeKitFacade.finish(transaction)

        return transaction
    }

    func startObservingTransactions() {
        storeKitFacade.startObservingTransactionUpdates()
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
            do {
                _ = try await self.userManager.obtainUser()
                try await self.purchasesService.send(transaction, userId: self.userIdProvider.getUserId())
            } catch {
                self.logger.error("Failed to report an observed transaction: " + error.message)
            }
        }
    }
}
