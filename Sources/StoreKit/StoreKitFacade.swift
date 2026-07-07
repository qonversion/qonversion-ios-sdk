//
//  StoreKitFacade.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import Foundation
import StoreKit

class StoreKitFacade: StoreKitFacadeInterface {
    
    let storeKitOldWrapper: StoreKitOldWrapperInterface?
    let storeKitWrapper: StoreKitWrapperInterface?
    let storeKitMapper: StoreKitMapperInterface
    var delegate: StoreKitFacadeDelegate?
    
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
    var loadedProducts: [String: StoreKit.Product]? { _loadedProducts as? [String: StoreKit.Product] }
    
    var _loadedProducts: [String: Any] = [:]
    
    var loadedOldProducts: [String: SKProduct] = [:]

    private var transactionUpdatesTask: Task<Void, Never>?
    
    init(storeKitOldWrapper: StoreKitOldWrapperInterface, storeKitMapper: StoreKitMapperInterface) {
        self.storeKitOldWrapper = storeKitOldWrapper
        self.storeKitWrapper = nil
        self.storeKitMapper = storeKitMapper
    }
    
    init(storeKitWrapper: StoreKitWrapperInterface, storeKitMapper: StoreKitMapperInterface) {
        self.storeKitOldWrapper = nil
        self.storeKitWrapper = storeKitWrapper
        self.storeKitMapper = storeKitMapper
    }
    
    func purchase(storeId: String) async throws -> Qonversion.Transaction {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeKitWrapper else {
            // StoreKit 1 purchase support lands with the SK1 parity pass.
            throw QonversionError(type: .storeKitUnavailable)
        }

        if loadedProducts?[storeId] == nil {
            _ = try await products(for: [storeId])
        }
        guard let product = loadedProducts?[storeId] else {
            throw QonversionError(type: .storeProductsLoadingFailed)
        }

        return try await storeKitWrapper.purchase(product: product)
    }

    func currentEntitlements() async -> [Qonversion.Transaction] {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeKitWrapper = storeKitWrapper else { return [] }

        return await storeKitWrapper.currentEntitlements()
    }
    
    func restore() async throws -> [Qonversion.Transaction] {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }

            return try await storeKitWrapper.restore()
        } else {
            return try await historicalData()
        }
    }
    
    func historicalData() async throws -> [Qonversion.Transaction] {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            return await storeKitWrapper.fetchAll()
        } else {
            guard let storeKitWrapper = storeKitOldWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            return try await withCheckedThrowingContinuation { continuation in
                storeKitWrapper.restore { [weak self] transactions, error in
                    if let error {
                        continuation.resume(throwing: QonversionError(type: .purchaseFailed, error: error))
                    } else {
                        // Best-effort SK1 mapping: the full domain transaction
                        // needs the SKProduct, available only for products
                        // loaded during this session.
                        let mapped: [Qonversion.Transaction] = transactions.compactMap { transaction in
                            guard let self, let product = self.loadedOldProducts[transaction.payment.productIdentifier] else { return nil }
                            return self.storeKitMapper.map(transaction, product: product)
                        }
                        continuation.resume(returning: mapped)
                    }
                }
            }
        }
    }
    
    #if os(iOS) || os(visionOS)
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {
        guard let storeKitWrapper = storeKitOldWrapper else { return }

        storeKitWrapper.presentCodeRedemptionSheet()
    }
    #endif
    
    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }

        try await storeKitWrapper.presentOfferCodeRedeemSheet(in: scene)
    }
    #endif
    
    func finish(_ transaction: Qonversion.Transaction) async {
        // Legacy transactions carry an SKPaymentTransaction handle; everything
        // else is routed to the StoreKit 2 wrapper, which resolves the
        // underlying transaction itself.
        if let skPaymentTransaction = transaction.skPaymentTransaction {
            storeKitOldWrapper?.finish(transaction: skPaymentTransaction)
            return
        }

        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeKitWrapper else {
            return
        }

        await storeKitWrapper.finish(transaction)
    }

    func startObservingTransactionUpdates() {
        guard transactionUpdatesTask == nil else { return }
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *),
              let storeKitWrapper else { return }

        // Observed transactions are handed to the delegate and NEVER finished
        // here: in Analytics mode the host app owns the transaction lifecycle,
        // and in subscription-management mode finishing happens only after the
        // backend confirms the purchase.
        transactionUpdatesTask = Task { [weak self] in
            for await transaction in storeKitWrapper.transactionUpdates() {
                guard let self, !Task.isCancelled else { return }
                self.delegate?.transactionUpdated(transaction)
            }
        }
    }

    func stopObservingTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
    }
    
    func products(for ids: [String]) async throws -> [StoreProductWrapper] {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *) {
            guard let storeKitWrapper = storeKitWrapper else { throw QonversionError(type: .storeKitUnavailable) }
            
            let products = try await storeKitWrapper.products(for: ids)
            products.forEach {
                _loadedProducts[$0.id] = $0
            }
            
            return products.map { StoreProductWrapper(_product: $0, oldProduct: nil) }
        } else {
            return try await skOneProducts(for: ids)
        }
    }

    /// StoreKit 1 products path, extracted so the continuation behavior is
    /// unit-testable on hosts where the StoreKit 2 branch is always available.
    func skOneProducts(for ids: [String]) async throws -> [StoreProductWrapper] {
        guard let storeKitWrapper = storeKitOldWrapper else { throw QonversionError(type: .storeKitUnavailable) }

        return try await withCheckedThrowingContinuation { continuation in
            storeKitWrapper.products(for: ids, completion: { [weak self] response, error in
                // The completion outlives the facade (the old wrapper is kept
                // alive by SKPaymentQueue), so a dead self MUST still resume
                // the continuation — otherwise the awaiting task hangs forever.
                guard let self else {
                    return continuation.resume(throwing: QonversionError(type: .storeProductsLoadingFailed))
                }

                if let error {
                    continuation.resume(throwing: QonversionError(type: .storeProductsLoadingFailed, error: error))
                } else {
                    guard let response else {
                        return continuation.resume(throwing: QonversionError(type: .storeProductsLoadingFailed))
                    }

                    response.products.forEach {
                        self.loadedOldProducts[$0.productIdentifier] = $0
                    }

                    let products: [StoreProductWrapper] = response.products.map { StoreProductWrapper(_product: nil, oldProduct: $0) }
                    continuation.resume(returning: products)
                }
            })
        }
    }
}

// MARK: - StoreKitWrapperDelegate

extension StoreKitFacade: StoreKitWrapperDelegate {
    
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) {
        delegate?.promoPurchaseIntent(product: product)
    }
}

// MARK: - StoreKitOldWrapperDelegate

extension StoreKitFacade: StoreKitOldWrapperDelegate {
    
    func handle(productsResponse: SKProductsResponse) {
        
    }
    
    func handle(restoreTransactionsError: any Error) {
        
    }
    
    func shouldAdd(storePayment: SKPayment, for product: SKProduct) -> Bool {
        return true
    }
    
    func handle(productsRequestError: any Error) {
        
    }
    
    func updated(transactions: [SKPaymentTransaction]) {
        
    }
}
