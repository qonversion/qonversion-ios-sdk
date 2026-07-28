//
//  StoreKitFacade.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 27.02.2024.
//

import Foundation
import StoreKit

// @unchecked: the product cache is lock-guarded; the delegate is weak.
class StoreKitFacade: StoreKitFacadeInterface, @unchecked Sendable {

    let storeKitWrapper: StoreKitWrapperInterface
    let storeKitMapper: StoreKitMapperInterface
    // Weak: the delegate (purchases manager) holds the facade itself.
    weak var delegate: StoreKitFacadeDelegate?

    // Written by concurrent products(for:) calls and read by purchase flows.
    private let productsLock = NSLock()
    private var _loadedProducts: [String: StoreKit.Product] = [:]

    var loadedProducts: [String: StoreKit.Product] {
        productsLock.lock()
        defer { productsLock.unlock() }
        return _loadedProducts
    }

    // Guarded so a concurrent start cannot double-subscribe.
    private let observationLock = NSLock()
    private var transactionUpdatesTask: Task<Void, Never>?
    private var storefrontTask: Task<Void, Never>?

    init(storeKitWrapper: StoreKitWrapperInterface, storeKitMapper: StoreKitMapperInterface) {
        self.storeKitWrapper = storeKitWrapper
        self.storeKitMapper = storeKitMapper
    }

    func purchase(storeId: String, options: Qonversion.PurchaseOptions) async throws -> Qonversion.Transaction {
        if loadedProducts[storeId] == nil {
            do {
                _ = try await products(for: [storeId])
            } catch {
                // Product.products(for:) throws raw StoreKit errors.
                throw StoreKitPurchaseOutcome.storeError(error, fallbackType: .storeProductsLoadingFailed)
            }
        }
        // The load succeeded and still returned nothing: the store has no such
        // product, rather than having failed to load it.
        guard let product: StoreKit.Product = loadedProducts[storeId] else {
            throw QonversionError(type: .storeProductNotAvailable)
        }

        return try await storeKitWrapper.purchase(product: product, options: options)
    }

    func isEligibleForIntroOffer(storeId: String) async -> Bool? {
        // Refetching per product would turn a check over N products into N
        // store requests.
        var product: StoreKit.Product? = loadedProducts[storeId]
        if product == nil {
            product = (try? await products(for: [storeId]))?.first?.product
        }
        guard let subscription: StoreKit.Product.SubscriptionInfo = product?.subscription else { return nil }

        return await subscription.isEligibleForIntroOffer
    }

    func storefrontUpdates() -> AsyncStream<Void> {
        return storeKitWrapper.storefrontUpdates()
    }

    func currentEntitlements() async -> [Qonversion.Transaction] {
        return await storeKitWrapper.currentEntitlements()
    }

    func restore() async throws -> [Qonversion.Transaction] {
        return try await storeKitWrapper.restore()
    }

    func historicalData() async throws -> [Qonversion.Transaction] {
        return await storeKitWrapper.fetchAll()
    }

    func map(_ verificationResult: VerificationResult<StoreKit.Transaction>) -> Qonversion.Transaction? {
        guard case .verified(let transaction) = verificationResult else { return nil }

        return storeKitMapper.map(transaction, jws: verificationResult.jwsRepresentation)
    }

    func unfinishedTransactions() async -> [Qonversion.Transaction] {
        return await storeKitWrapper.fetchUnfinished()
    }

    #if os(iOS) || os(visionOS)
    func presentCodeRedemptionSheet() {
        SKPaymentQueue.default().presentCodeRedemptionSheet()
    }
    #endif

    #if os(iOS) || os(visionOS)
    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await storeKitWrapper.presentOfferCodeRedeemSheet(in: scene)
    }
    #endif

    #if os(visionOS)
    @MainActor
    func setPurchaseConfirmationScene(_ scene: UIScene?) {
        storeKitWrapper.setPurchaseConfirmationScene(scene)
    }
    #endif

    func finish(_ transaction: Qonversion.Transaction) async {
        await storeKitWrapper.finish(transaction)
    }

    func clearLoadedProducts() {
        productsLock.lock()
        defer { productsLock.unlock() }
        _loadedProducts = [:]
    }

    private func storeLoadedProducts(_ products: [StoreKit.Product]) {
        productsLock.lock()
        defer { productsLock.unlock() }
        products.forEach {
            _loadedProducts[$0.id] = $0
        }
    }

    func startObservingTransactionUpdates() {
        observationLock.lock()
        defer { observationLock.unlock() }

        guard transactionUpdatesTask == nil else { return }

        // NEVER finished here: Analytics mode leaves the lifecycle to the host,
        // subscription management finishes only after the backend ack.
        let wrapper: StoreKitWrapperInterface = storeKitWrapper
        transactionUpdatesTask = Task { [weak self] in
            for await transaction in wrapper.transactionUpdates() {
                guard let self, !Task.isCancelled else { return }
                self.delegate?.transactionUpdated(transaction)
            }
        }

        // Prices, availability and offers are per-storefront: everything
        // cached about products dies with the storefront it was loaded for.
        storefrontTask = Task { [weak self] in
            for await _ in wrapper.storefrontUpdates() {
                guard let self, !Task.isCancelled else { return }
                self.clearLoadedProducts()
            }
        }

        // StoreKit 2 exposes promo intents from iOS 16.4 only; 15.0–16.3 is a
        // known gap.
        #if !os(watchOS) && !os(tvOS) && !os(visionOS)
        if #available(iOS 16.4, macOS 14.4, *) {
            storeKitWrapper.subscribeToPromoPurchases()
        }
        #endif
    }

    func stopObservingTransactionUpdates() {
        observationLock.lock()
        defer { observationLock.unlock() }

        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
        storefrontTask?.cancel()
        storefrontTask = nil
        #if !os(watchOS) && !os(tvOS) && !os(visionOS)
        storeKitWrapper.unsubscribeFromPromoPurchases()
        #endif
    }

    func products(for ids: [String]) async throws -> [StoreProductWrapper] {
        let products: [StoreKit.Product] = try await storeKitWrapper.products(for: ids)
        storeLoadedProducts(products)

        return products.map { StoreProductWrapper(product: $0) }
    }
}

// MARK: - StoreKitWrapperDelegate

#if !os(watchOS) && !os(tvOS) && !os(visionOS)
extension StoreKitFacade: StoreKitWrapperDelegate {

    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) {
        delegate?.promoPurchaseIntent(product: product)
    }
}
#endif
