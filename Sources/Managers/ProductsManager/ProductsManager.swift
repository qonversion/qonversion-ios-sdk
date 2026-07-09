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
        return loadedProducts
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
        
        do {
            let resultProducts: [Qonversion.Product] = try await storeEnriched(products)
            loadedProducts = resultProducts
            
            return resultProducts
        } catch {
            logger.error(error.localizedDescription)
        }
        
        loadedProducts = products
        
        return products
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
        let productIds: [String] = products.map { $0.storeId }
        let storeProducts: [StoreProductWrapper] = try await storeKitFacade.products(for: productIds)

        var resultProducts: [Qonversion.Product] = []

        for var product in products {
            guard let storeProductWrapper: StoreProductWrapper = storeProducts.first(where: { $0.id == product.storeId }) else { continue }

            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *), let storeProduct = storeProductWrapper.product {
                product.enrich(storeProduct: storeProduct)
            } else if let storeProduct: SKProduct = storeProductWrapper.oldProduct {
                product.enrich(skProduct: storeProduct)
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
        loadedProducts = []
    }
}

