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

    /// Scoped by apiKey: an app that switches project keys must never see the
    /// other project's catalog. The old unscoped blob is deliberately ignored
    /// rather than migrated — it was never served publicly.
    private let productsKey: String
    
    private let lock = NSLock()
    private var _loadedProducts: [Qonversion.Product] = []
    private var _loadedProductPermissions: [String: [String]]?
    private var _productsTask: Task<[Qonversion.Product], Error>?
    private var _storefrontTask: Task<Void, Never>?
    private var _permissionsTask: Task<Void, Never>?

    /// When the last on-demand mapping load was started. The reload is driven
    /// by demand, so a permanently failing backend would otherwise be asked
    /// once per entitlements check.
    private var lastPermissionsLoadAttempt: Date?

    /// Minimum gap between two on-demand mapping loads.
    private static let permissionsReloadInterval: TimeInterval = 60

    /// Bumped on every user switch: a load started for the previous user must
    /// not cache or persist its catalog for the new one.
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
    
    init(apiKey: String, productsService: ProductsServiceInterface, storeKitFacade: StoreKitFacadeInterface, localStorage: LocalStorageInterface, fallbackService: FallbackServiceInterface, logger: LoggerWrapper) {
        self.productsKey = Constants.productsKey.rawValue + "." + apiKey
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

        // Persisted catalog first, bundled fallback second. Every path serving
        // a catalog reports its unpriceable rows, so the warning does not
        // depend on which call happened to run first.
        if let persisted: [Qonversion.Product] = persistedCatalog(), !persisted.isEmpty {
            reportProductsWithoutStoreId(persisted)

            return persisted
        }

        let fallbackProducts: [Qonversion.Product] = fallbackService.obtainFallbackData()?.products ?? []
        reportProductsWithoutStoreId(fallbackProducts)

        return fallbackProducts
    }

    func isFallbackFileAccessible() -> Bool {
        return fallbackService.obtainFallbackData() != nil
    }

    func loadProductPermissions() async {
        // Single-flight: the launch refresh and an on-demand reload may land
        // together, and N entitlements checks must cost one request.
        let task: Task<Void, Never> = joinedPermissionsTask()
        await task.value
        clearPermissionsTask(task)
    }

    private func joinedPermissionsTask() -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }

        if let inFlight: Task<Void, Never> = _permissionsTask {
            return inFlight
        }

        lastPermissionsLoadAttempt = Date()
        let task = Task { [weak self] () -> Void in
            await self?.performLoadProductPermissions()
        }
        _permissionsTask = task

        return task
    }

    private func clearPermissionsTask(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        if _permissionsTask == task {
            _permissionsTask = nil
        }
    }

    private func performLoadProductPermissions() async {
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

    private func shouldAwaitPermissionsLoad() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // A load is already running — joining it costs nothing and answers this
        // call, so the throttle does not apply.
        if _permissionsTask != nil { return true }
        guard let lastPermissionsLoadAttempt else { return true }

        return Date().timeIntervalSince(lastPermissionsLoadAttempt) >= Self.permissionsReloadInterval
    }

    private func storeLoadedPermissions(_ mapping: [String: [String]]) {
        lock.lock()
        defer { lock.unlock() }
        _loadedProductPermissions = mapping
    }

    func productPermissions() async -> [String: [String]] {
        if let cached: [String: [String]] = cachedProductPermissions(), !cached.isEmpty {
            return cached
        }
        // Nothing anywhere — not in memory, not persisted, not bundled. The
        // load is retried on demand rather than once per launch, but not on
        // every single call: a permanently failing backend must not turn each
        // entitlements check into a request.
        guard shouldAwaitPermissionsLoad() else { return [:] }

        await loadProductPermissions()

        return cachedProductPermissions() ?? [:]
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
            // Neither snapshot may shadow the API: the in-memory cache stays
            // empty so the next call retries.
            //
            // Two accepted trade-offs: the persisted catalog has no staleness
            // bound, and it beats the bundled file even when that file is newer.
            if let persistedProducts: [Qonversion.Product] = persistedCatalog(ifGenerationIs: generation), !persistedProducts.isEmpty {
                logger.warning("Products request failed, using the catalog of the last successful load: " + error.message)
                reportProductsWithoutStoreId(persistedProducts)

                return await enriched(persistedProducts)
            }

            guard let fallbackProducts: [Qonversion.Product] = fallbackService.obtainFallbackData()?.products, !fallbackProducts.isEmpty else {
                throw error
            }
            logger.warning("Products request failed, using the bundled fallback file: " + error.message)
            reportProductsWithoutStoreId(fallbackProducts)

            return await enriched(fallbackProducts)
        }

        reportProductsWithoutStoreId(products)

        // Persisted for the offline local entitlements calculation; the
        // StoreKit enrichment does not survive encoding and is not needed there.
        persist(products, ifGenerationIs: generation)

        do {
            let resultProducts: [Qonversion.Product] = try await storeEnriched(products)
            store(resultProducts, ifGenerationIs: generation)

            return resultProducts
        } catch {
            // Answered but deliberately NOT cached: caching the unenriched
            // catalog would make a transient store outage last the session.
            logger.error("Store products could not be loaded, returning the catalog unenriched: " + error.message)

            return products
        }
    }

    /// An empty storeId is legal (Stripe- or Play-only) but far more often a
    /// misconfigured row, so it is never swallowed silently.
    private func reportProductsWithoutStoreId(_ products: [Qonversion.Product]) {
        let unlinked: [String] = products.filter { $0.storeId.isEmpty }.map { $0.qonversionId }
        guard !unlinked.isEmpty else { return }

        logger.warning("These products carry no App Store product id and cannot be priced by the store: " + unlinked.joined(separator: ", "))
    }

    /// Unchecked read — callers holding a generation snapshot must use the
    /// checked overload below instead.
    private func persistedCatalog() -> [Qonversion.Product]? {
        return try? localStorage.object(forKey: productsKey, dataType: [Qonversion.Product].self)
    }

    /// The generation check and the read are one step: a user switch between
    /// them would hand the other user's catalog to this caller.
    private func persistedCatalog(ifGenerationIs generation: Int) -> [Qonversion.Product]? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return nil }

        // Safe under the lock: the unchecked read never takes it.
        return persistedCatalog()
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cacheGeneration
    }

    /// The generation check and the write are one step: a user switch landing
    /// between them would resurrect the previous user's catalog.
    private func persist(_ products: [Qonversion.Product], ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return }

        try? localStorage.set(products, forKey: productsKey)
    }

    private func store(_ products: [Qonversion.Product], ifGenerationIs generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return }

        _loadedProducts = products
    }

    func checkTrialIntroEligibility(productIds: [String]) async throws -> [String: Qonversion.IntroEligibilityStatus] {
        // The catalog is a lookup here — it maps a Qonversion id to a store id,
        // nothing more. An unreachable one is the documented ".unknown" case
        // ("the store did not answer, or the id is not in your catalog"), not a
        // reason to fail the whole paywall check.
        var allProducts: [Qonversion.Product] = (try? await products()) ?? []
        if allProducts.isEmpty {
            allProducts = cachedProducts()
        }
        if allProducts.isEmpty {
            logger.warning("Intro eligibility was requested with no products catalog available: every status is .unknown.")
        }

        var result: [String: Qonversion.IntroEligibilityStatus] = [:]
        var storeIdsToCheck: [String: String] = [:]
        for productId in productIds {
            guard let product: Qonversion.Product = allProducts.first(where: { $0.qonversionId == productId }) else {
                // .unknown alone hides a typo: the caller cannot tell "the
                // store would not say" from "not in your catalog at all".
                logger.warning("Intro eligibility was requested for \"" + productId + "\", which is not in the products catalog.")
                result[productId] = .unknown
                continue
            }
            guard product.isStoreProductLinked else {
                result[productId] = .unknown
                continue
            }

            guard product.subscription?.introductoryOffer != nil else {
                result[productId] = .nonIntroOrTrialProduct
                continue
            }

            storeIdsToCheck[productId] = product.storeId
        }

        let facade: StoreKitFacadeInterface = storeKitFacade
        let eligibilities: [String: Qonversion.IntroEligibilityStatus] = await Self.introEligibilities(for: storeIdsToCheck) { storeId in
            await facade.isEligibleForIntroOffer(storeId: storeId)
        }
        eligibilities.forEach { result[$0.key] = $0.value }

        return result
    }

    /// Checks CONCURRENTLY: serial checks made the call as slow as the paywall
    /// is long.
    static func introEligibilities(
        for storeIdsByProductId: [String: String],
        check: @escaping @Sendable (String) async -> Bool?
    ) async -> [String: Qonversion.IntroEligibilityStatus] {
        return await withTaskGroup(of: (String, Qonversion.IntroEligibilityStatus).self) { group in
            for (productId, storeId) in storeIdsByProductId {
                group.addTask {
                    switch await check(storeId) {
                    case .some(true):
                        return (productId, .eligible)
                    case .some(false):
                        return (productId, .ineligible)
                    case .none:
                        return (productId, .unknown)
                    }
                }
            }

            var collected: [String: Qonversion.IntroEligibilityStatus] = [:]
            for await eligibility in group {
                collected[eligibility.0] = eligibility.1
            }

            return collected
        }
    }

    /// Prices, availability and offers are per-storefront and must be refetched
    /// after a change.
    func startObservingStorefrontChanges() {
        // The check and the assignment are one step, or a concurrent second
        // start leaks an observation task.
        lock.lock()
        defer { lock.unlock() }
        guard _storefrontTask == nil else { return }

        _storefrontTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.storeKitFacade.storefrontUpdates() {
                guard !Task.isCancelled else { return }
                self.dropStoreEnrichment()
            }
        }
    }

    private func dropStoreEnrichment() {
        lock.lock()
        defer { lock.unlock() }
        // Only the enriched copy dies. The generation bump and the cleared task
        // stop a load started before the change from writing the old
        // storefront's prices straight back, or being joined after it.
        cacheGeneration += 1
        _loadedProducts = []
        _productsTask = nil
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
        var missingStoreIds: [String] = []

        // Products the store does not know stay in the list unenriched — the
        // catalog is backend-driven.
        for var product in products {
            if let storeProduct: StoreKit.Product = storeProducts.first(where: { $0.id == product.storeId })?.product {
                product.enrich(storeProduct: storeProduct)
            } else if !product.storeId.isEmpty {
                missingStoreIds.append(product.storeId)
            }

            resultProducts.append(product)
        }

        // The half-enriched list IS cached — an unpriceable product is a real
        // state — but it is almost always a misconfiguration, so it is named.
        if !missingStoreIds.isEmpty {
            logger.warning("The App Store returned no product for these ids, so they stay unpriced: " + missingStoreIds.joined(separator: ", "))
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
        defer { lock.unlock() }

        cacheGeneration += 1
        _loadedProducts = []
        // The in-flight load belongs to the previous user — the next caller
        // must start its own.
        _productsTask = nil
        localStorage.removeObject(forKey: productsKey)
    }
}

