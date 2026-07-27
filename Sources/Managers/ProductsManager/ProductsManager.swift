//
//  ProductsManager.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 22.04.2024.
//

import Foundation
import StoreKit

fileprivate enum Constants: String {
    case productPermissionsKey = "qonversion.keys.productsPermissions"
    case productsKey = "qonversion.keys.products"
}

// @unchecked: the caches are lock-guarded.
final class ProductsManager: ProductsManagerInterface, ProductsDataSource, @unchecked Sendable {
    
    let productsService: ProductsServiceInterface
    let storeKitFacade: StoreKitFacadeInterface
    let localStorage: LocalStorageInterface
    private let fallbackService: FallbackServiceInterface
    private let logger: LoggerWrapper
    
    // Read by the local entitlements calculation and by concurrent products()
    // calls, cleared from the user-change notification thread.
    private let lock = NSLock()
    private var _loadedProducts: [Qonversion.Product] = []
    private var _loadedProductPermissions: [String: [String]]?
    private var _productsTask: Task<[Qonversion.Product], Error>?

    /// Bumped on every user switch: a load that started for the previous user
    /// must not cache or persist its (possibly personalized) catalog for the
    /// new one.
    private var cacheGeneration = 0

    var loadedProducts: [Qonversion.Product] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _loadedProducts
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _loadedProducts = newValue
        }
    }
    
    init(productsService: ProductsServiceInterface, storeKitFacade: StoreKitFacadeInterface, localStorage: LocalStorageInterface, fallbackService: FallbackServiceInterface, logger: LoggerWrapper) {
        self.productsService = productsService
        self.storeKitFacade = storeKitFacade
        self.localStorage = localStorage
        self.fallbackService = fallbackService
        self.logger = logger
    }
    
    func cachedProducts() -> [Qonversion.Product] {
        if !loadedProducts.isEmpty {
            return loadedProducts
        }

        // The offline cold start is exactly what the local entitlements
        // calculation exists for — answer from the persisted catalog, then
        // from the bundled fallback file.
        if let persisted: [Qonversion.Product] = try? localStorage.object(forKey: Constants.productsKey.rawValue, dataType: [Qonversion.Product].self), !persisted.isEmpty {
            return persisted
        }

        return fallbackService.obtainFallbackData()?.products ?? []
    }

    func isFallbackFileAccessible() -> Bool {
        return fallbackService.obtainFallbackData() != nil
    }

    func loadProductPermissions() async {
        do {
            let mapping: [String: [String]] = try await productsService.productPermissions()
            storeLoadedPermissions(mapping)
            try localStorage.set(mapping, forKey: Constants.productPermissionsKey.rawValue)
        } catch {
            // The previously cached mapping stays — it still powers local
            // entitlements calculation while the backend is unreachable.
            logger.warning("Failed to refresh product permissions mapping: " + error.message)
        }
    }

    private func storeLoadedPermissions(_ mapping: [String: [String]]) {
        lock.lock()
        defer { lock.unlock() }
        _loadedProductPermissions = mapping
    }

    func cachedProductPermissions() -> [String: [String]]? {
        lock.lock()
        if let loaded: [String: [String]] = _loadedProductPermissions {
            lock.unlock()
            return loaded
        }
        lock.unlock()

        if let persisted = try? localStorage.object(forKey: Constants.productPermissionsKey.rawValue, dataType: [String: [String]].self) {
            lock.lock()
            _loadedProductPermissions = persisted
            lock.unlock()
            return persisted
        }

        // First launch without a network connection: the bundled snapshot
        // keeps the local entitlements calculation alive.
        return fallbackService.obtainFallbackData()?.productsPermissions
    }

    func products() async throws -> [Qonversion.Product] {
        guard loadedProducts.isEmpty else {
            return loadedProducts
        }

        // Single-flight: N concurrent callers share one API + StoreKit round.
        let task: Task<[Qonversion.Product], Error> = joinedProductsTask()
        defer { clearProductsTask(task) }

        return try await task.value
    }

    private func joinedProductsTask() -> Task<[Qonversion.Product], Error> {
        lock.lock()
        defer { lock.unlock() }

        if let inFlight: Task<[Qonversion.Product], Error> = _productsTask {
            return inFlight
        }

        let task = Task { [weak self] () throws -> [Qonversion.Product] in
            guard let self else { return [] }
            return try await self.loadProducts()
        }
        _productsTask = task

        return task
    }

    private func clearProductsTask(_ task: Task<[Qonversion.Product], Error>) {
        lock.lock()
        defer { lock.unlock() }
        if _productsTask == task {
            _productsTask = nil
        }
    }

    private func loadProducts() async throws -> [Qonversion.Product] {
        // Snapshotted before the first suspension: everything below writes
        // user-scoped state, and a user switch may land mid-request.
        let generation: Int = currentGeneration()

        let products: [Qonversion.Product]
        do {
            products = try await productsService.products()
        } catch {
            // The bundled snapshot answers this call only — it must not shadow
            // the API, so the in-memory cache stays empty and the next call retries.
            guard let fallbackProducts: [Qonversion.Product] = fallbackService.obtainFallbackData()?.products, !fallbackProducts.isEmpty else {
                throw error
            }
            logger.warning("Products request failed, using the bundled fallback file: " + error.message)
            return await enriched(fallbackProducts)
        }
        
        // Persisted for the offline local entitlements calculation on the
        // next launches (StoreKit enrichment does not survive encoding —
        // the wire fields are enough for the calculation).
        if isCurrent(generation) {
            try? localStorage.set(products, forKey: Constants.productsKey.rawValue)
        }

        do {
            let resultProducts: [Qonversion.Product] = try await storeEnriched(products)
            store(resultProducts, ifGenerationIs: generation)

            return resultProducts
        } catch {
            logger.error(error.localizedDescription)
        }

        store(products, ifGenerationIs: generation)

        return products
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cacheGeneration
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == cacheGeneration
    }

    private func store(_ products: [Qonversion.Product], ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return }

        _loadedProducts = products
    }

    func checkTrialIntroEligibility(productIds: [String]) async throws -> [String: Qonversion.IntroEligibilityStatus] {
        let allProducts: [Qonversion.Product] = try await products()

        var result: [String: Qonversion.IntroEligibilityStatus] = [:]
        for productId in productIds {
            guard let product: Qonversion.Product = allProducts.first(where: { $0.qonversionId == productId }), product.isStoreProductLinked else {
                result[productId] = .unknown
                continue
            }

            guard product.subscription?.introductoryOffer != nil else {
                result[productId] = .nonIntroOrTrialProduct
                continue
            }

            switch await storeKitFacade.isEligibleForIntroOffer(storeId: product.storeId) {
            case .some(true):
                result[productId] = .eligible
            case .some(false):
                result[productId] = .ineligible
            case .none:
                result[productId] = .unknown
            }
        }

        return result
    }

    /// Best-effort StoreKit enrichment that never fails: on a store error the
    /// unenriched products are returned as-is.
    private func enriched(_ products: [Qonversion.Product]) async -> [Qonversion.Product] {
        do {
            return try await storeEnriched(products)
        } catch {
            logger.error(error.localizedDescription)
            return products
        }
    }

    private func storeEnriched(_ products: [Qonversion.Product]) async throws -> [Qonversion.Product] {
        let productIds: [String] = products.filter { !$0.storeId.isEmpty }.map { $0.storeId }
        let storeProducts: [StoreProductWrapper] = try await storeKitFacade.products(for: productIds)

        var resultProducts: [Qonversion.Product] = []

        // Products the store does not know (e.g. Stripe-only ones with no
        // App Store id) stay in the list unenriched — the catalog is
        // backend-driven.
        for var product in products {
            if let storeProduct: StoreKit.Product = storeProducts.first(where: { $0.id == product.storeId })?.product {
                product.enrich(storeProduct: storeProduct)
            }

            resultProducts.append(product)
        }

        return resultProducts
    }
}

// MARK: - UserChangedObserver

extension ProductsManager: UserChangedObserver {

    func userDidChange() {
        // Products may be personalized (experiments); the mapping is
        // project-scoped and stays.
        lock.lock()
        cacheGeneration += 1
        _loadedProducts = []
        // The in-flight load belongs to the previous user — the next caller
        // must start its own instead of joining it.
        _productsTask = nil
        lock.unlock()

        localStorage.removeObject(forKey: Constants.productsKey.rawValue)
    }
}

