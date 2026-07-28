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

    /// The key the catalog of the last successful load is persisted under,
    /// scoped by apiKey exactly like the offline requests queue: products()
    /// serves this blob publicly, and an app that switches project keys must
    /// never see the other project's catalog on its paywall.
    ///
    /// The blob earlier versions wrote under the unscoped key is ignored
    /// rather than migrated: it was never served publicly (only the local
    /// entitlements calculation read it), so the whole cost is one API round
    /// on the first launch after the update.
    private let productsKey: String
    
    // Read by the local entitlements calculation and by concurrent products()
    // calls, cleared from the user-change notification thread.
    private let lock = NSLock()
    private var _loadedProducts: [Qonversion.Product] = []
    private var _loadedProductPermissions: [String: [String]]?
    private var _productsTask: Task<[Qonversion.Product], Error>?
    private var _storefrontTask: Task<Void, Never>?

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

        // The offline cold start is exactly what the local entitlements
        // calculation exists for — answer from the persisted catalog, then
        // from the bundled fallback file.
        //
        // Both snapshots report their unpriceable rows, like the failed-load
        // path does: the rule is that every path serving a catalog names them,
        // and a row visible here but not there would be reported or not purely
        // by which call happened to run first.
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
            // Neither snapshot answers more than this call — they must not
            // shadow the API, so the in-memory cache stays empty and the next
            // call retries.
            //
            // Reported on these paths too, not only on the API one: they are
            // precisely where a product row with neither `store_id` nor
            // `apple_product_id` comes from, and they return early.

            // The catalog of the last successful load comes first: it is what
            // the backend actually said for THIS user, and without it an
            // offline cold start empties the paywall of every app that does
            // not bundle the fallback file.
            //
            // Two accepted trade-offs, chosen rather than missed:
            //   * no staleness bound — a catalog persisted months ago is still
            //     served, because a stale price beats an empty paywall and the
            //     next successful load overwrites it anyway;
            //   * it beats the bundled file even when the bundled file is
            //     newer, because it is the only snapshot the backend produced
            //     for this project's live configuration.
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

        // Persisted for the offline local entitlements calculation on the
        // next launches (StoreKit enrichment does not survive encoding —
        // the wire fields are enough for the calculation).
        persist(products, ifGenerationIs: generation)

        do {
            let resultProducts: [Qonversion.Product] = try await storeEnriched(products)
            store(resultProducts, ifGenerationIs: generation)

            return resultProducts
        } catch {
            // Answer this caller with what the backend gave, but do NOT make
            // it the cache: a StoreKit outage is transient, and caching the
            // unenriched catalog made it permanent for the whole session —
            // prices and offers never came back however long the store stayed
            // healthy afterwards. The next products() call retries the
            // enrichment.
            logger.error("Store products could not be loaded, returning the catalog unenriched: " + error.message)

            return products
        }
    }

    /// An empty storeId is a product the store can never price. It is legal
    /// (a Stripe- or Play-only product) but it is far more often a fallback
    /// file row with neither `store_id` nor `apple_product_id`, so it is
    /// never swallowed silently.
    private func reportProductsWithoutStoreId(_ products: [Qonversion.Product]) {
        let unlinked: [String] = products.filter { $0.storeId.isEmpty }.map { $0.qonversionId }
        guard !unlinked.isEmpty else { return }

        logger.warning("These products carry no App Store product id and cannot be priced by the store: " + unlinked.joined(separator: ", "))
    }

    /// The catalog of the last successful load, cleared on a user switch and
    /// stored with no expiry: a stale catalog beats an empty paywall.
    ///
    /// Clearing alone does not make the read safe for a load that SPANS a
    /// switch — by the time such a load reads back, the new user may have
    /// persisted its own catalog under the key. Callers holding a generation
    /// snapshot must use the checked overload below.
    private func persistedCatalog() -> [Qonversion.Product]? {
        return try? localStorage.object(forKey: productsKey, dataType: [Qonversion.Product].self)
    }

    /// The generation check and the read are one step, exactly like persist()
    /// and store(): a user switch landing between them hands the catalog
    /// behind the key — by then the OTHER user's — to a caller that started
    /// under the previous one. On a mismatch the caller falls through to the
    /// project-scoped bundled file, or gets the error.
    private func persistedCatalog(ifGenerationIs generation: Int) -> [Qonversion.Product]? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == cacheGeneration else { return nil }

        // Reads under the lock: the read itself never takes it.
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
        let allProducts: [Qonversion.Product] = try await products()

        var result: [String: Qonversion.IntroEligibilityStatus] = [:]
        var storeIdsToCheck: [String: String] = [:]
        for productId in productIds {
            guard let product: Qonversion.Product = allProducts.first(where: { $0.qonversionId == productId }) else {
                // .unknown alone hides a typo in the product id: the caller
                // cannot tell "the store would not say" from "this product is
                // not in your Qonversion catalog at all".
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

    /// Asks the store about every product that needs a check CONCURRENTLY:
    /// asking one after another made the check as slow as the paywall is long.
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

    /// The storefront defines prices, availability and offers: everything
    /// enriched from the store must be refetched after a change.
    func startObservingStorefrontChanges() {
        // The check and the assignment are one step: a concurrent second start
        // would otherwise leak an observation task.
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
        // The catalog itself is backend-driven and stays; only the enriched
        // copy dies, so the next products() call refetches the store data.
        //
        // The generation bump and the cleared task are what make that true: a
        // load that started BEFORE the storefront changed carries the old
        // storefront's prices and offers, and would otherwise write them
        // straight back into the cache this just emptied — or be joined by a
        // caller arriving after the change.
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

        // Products the store does not know (e.g. Stripe-only ones with no
        // App Store id) stay in the list unenriched — the catalog is
        // backend-driven.
        for var product in products {
            if let storeProduct: StoreKit.Product = storeProducts.first(where: { $0.id == product.storeId })?.product {
                product.enrich(storeProduct: storeProduct)
            } else if !product.storeId.isEmpty {
                missingStoreIds.append(product.storeId)
            }

            resultProducts.append(product)
        }

        // The half-enriched list IS cached — the catalog is authoritative and
        // a product the store refuses to price is a real state. But it is
        // almost always a misconfiguration (the id does not exist in App Store
        // Connect, or the agreement is not signed), and it shows up as a
        // paywall with no price, so it is named rather than left to be
        // guessed at.
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
        // must start its own instead of joining it.
        _productsTask = nil
        localStorage.removeObject(forKey: productsKey)
    }
}

