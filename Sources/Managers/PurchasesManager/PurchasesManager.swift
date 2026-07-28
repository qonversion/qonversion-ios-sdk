//
//  PurchasesManager.swift
//  Qonversion
//

import Foundation
import StoreKit

fileprivate enum Constants: String {
    case historicalDataSyncedKey = "qonversion.keys.historicalDataSynced"
    // The transactions the host has already been told about, persisted:
    // StoreKit re-delivers every unfinished transaction on each cold start.
    case surfacedTransactionsKey = "qonversion.keys.surfacedTransactions"
}

fileprivate enum IntConstants: Int {
    /// Bounds the surfaced-transactions set; the oldest ids are dropped first.
    case maxSurfacedTransactions = 200
}

// @unchecked: mutable state lives in the actor gate and lock-guarded storages.
final class PurchasesManager: PurchasesManagerInterface, @unchecked Sendable {

    private let purchasesService: PurchasesServiceInterface
    private let storeKitFacade: StoreKitFacadeInterface
    private let userManager: UserManagerInterface
    private let entitlementsManager: EntitlementsManagerInterface
    private let userIdProvider: UserIdProvider
    private let launchModeProvider: LaunchModeProvider
    private let purchaseAssociationsStorage: PurchaseAssociationsStorage
    private let localStorage: LocalStorageInterface
    private let logger: LoggerWrapper

    // Joined by concurrent restore() calls; guarded by restoreTaskLock.
    private let restoreTaskLock = NSLock()
    private var restoreTask: Task<[String: Qonversion.Entitlement], Error>?

    // Products with a payment sheet in flight; a second purchase of the same
    // product must not present a second sheet. Helpers stay sync: NSLock must
    // not be held across a suspension point.
    private let purchasingLock = NSLock()
    private var purchasingStoreIds: Set<String> = []

    private func beginPurchasing(_ storeId: String) -> Bool {
        purchasingLock.lock()
        defer { purchasingLock.unlock() }
        guard !purchasingStoreIds.contains(storeId) else { return false }
        purchasingStoreIds.insert(storeId)
        return true
    }

    private func endPurchasing(_ storeId: String) {
        purchasingLock.lock()
        defer { purchasingLock.unlock() }
        purchasingStoreIds.remove(storeId)
    }

    private func isPurchasing(_ storeId: String) -> Bool {
        purchasingLock.lock()
        defer { purchasingLock.unlock() }
        return purchasingStoreIds.contains(storeId)
    }

    private let reportsGate: TransactionReportsGate

    // Guards the persisted set of transactions already handed to the host.
    private let surfacedLock = NSLock()

    /// True when this transaction had not been surfaced yet — and marks it
    /// surfaced. Persisted: StoreKit re-delivers unfinished transactions on
    /// every launch, and Analytics mode never finishes any.
    private func markSurfacedIfNew(_ transactionId: String) -> Bool {
        surfacedLock.lock()
        defer { surfacedLock.unlock() }

        var surfaced: [String] = storedSurfacedTransactions()
        guard !surfaced.contains(transactionId) else { return false }

        surfaced.append(transactionId)
        if surfaced.count > IntConstants.maxSurfacedTransactions.rawValue {
            surfaced.removeFirst(surfaced.count - IntConstants.maxSurfacedTransactions.rawValue)
        }
        try? localStorage.set(surfaced, forKey: Constants.surfacedTransactionsKey.rawValue)

        return true
    }

    private func storedSurfacedTransactions() -> [String] {
        return (try? localStorage.object(forKey: Constants.surfacedTransactionsKey.rawValue, dataType: [String].self)) ?? []
    }

    // Buffered: an approval processed during launch, before the host
    // subscribes, must not be dropped.
    private let deferredPurchasesMulticast = AsyncMulticast<Qonversion.DeferredPurchase>(replaysBacklog: true)

    // Buffered until the first subscriber — an intent arriving at app start
    // must not be lost.
    private let promoIntentsMulticast = AsyncMulticast<Qonversion.PromoPurchaseIntent>(replaysBacklog: true)

    func deferredPurchases() -> AsyncStream<Qonversion.DeferredPurchase> {
        return deferredPurchasesMulticast.stream()
    }

    /// The entitlements-only projection of the deferred purchases: one
    /// subscription of its own, so both streams stay independent.
    func entitlementsUpdates() -> AsyncStream<[String: Qonversion.Entitlement]> {
        return AsyncStream { continuation in
            // Subscribing here does not consume what deferredPurchases() is
            // owed: AsyncMulticast replays its backlog to every subscriber.
            let purchases: AsyncStream<Qonversion.DeferredPurchase> = self.deferredPurchasesMulticast.stream()
            let task = Task {
                for await purchase in purchases {
                    continuation.yield(purchase.entitlements)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func promoPurchaseIntents() -> AsyncStream<Qonversion.PromoPurchaseIntent> {
        #if os(watchOS) || os(tvOS) || os(visionOS)
        // No promoted purchases on these platforms; the stream must finish
        // rather than hang `for await` forever.
        return AsyncStream { $0.finish() }
        #else
        return promoIntentsMulticast.stream()
        #endif
    }

    init(
        purchasesService: PurchasesServiceInterface,
        storeKitFacade: StoreKitFacadeInterface,
        userManager: UserManagerInterface,
        entitlementsManager: EntitlementsManagerInterface,
        userIdProvider: UserIdProvider,
        launchModeProvider: LaunchModeProvider,
        purchaseAssociationsStorage: PurchaseAssociationsStorage,
        localStorage: LocalStorageInterface,
        reportsGate: TransactionReportsGate,
        logger: LoggerWrapper
    ) {
        self.purchasesService = purchasesService
        self.storeKitFacade = storeKitFacade
        self.userManager = userManager
        self.entitlementsManager = entitlementsManager
        self.userIdProvider = userIdProvider
        self.launchModeProvider = launchModeProvider
        self.purchaseAssociationsStorage = purchaseAssociationsStorage
        self.localStorage = localStorage
        self.reportsGate = reportsGate
        self.logger = logger
    }

    @discardableResult
    func purchase(_ product: Qonversion.Product, options: Qonversion.PurchaseOptions?) async throws -> Qonversion.PurchaseResult {
        guard beginPurchasing(product.storeId) else {
            throw QonversionError(type: .purchaseInProgress)
        }
        defer { endPurchasing(product.storeId) }

        if launchModeProvider.launchMode == .analytics {
            logger.warning("Making purchases via Qonversion in the Analytics mode can lead to an inconsistent state in the store. Consider switching to the Subscription management mode.")
        }

        // The uid is captured HERE: a logout during the payment sheet must not
        // reroute the report to the next anonymous user.
        _ = try await userManager.obtainUser()
        let userId: String = userIdProvider.getUserId()

        // Persisted for the whole lifecycle: a report happening after a
        // relaunch must still carry the paywall context of THIS call.
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
            // A pending purchase arrives later via the listener and must keep
            // its associations; any other failure never matches them again.
            if (error as? QonversionError)?.type != .purchasePending {
                purchaseAssociationsStorage.remove(for: product.storeId)
            }
            throw StoreKitPurchaseOutcome.storeError(error, fallbackType: .purchaseFailed)
        }

        // Already surfaced by this call's result: a later re-delivery through
        // the updates listener must not repeat it as a deferred purchase.
        if let id: String = transaction.id {
            _ = markSurfacedIfNew(id)
        }

        // The id is claimed BEFORE the report goes out: a concurrent restore
        // or sweep must not report the same transaction. A failed report
        // releases the id for retries.
        let gateTaken: Bool
        if let id: String = transaction.id {
            gateTaken = reportsGate.tryTake(id)
            // Another flow owns the report and will finish the transaction;
            // this call still answers with entitlements.
            guard gateTaken else {
                return await purchaseResult(for: transaction)
            }
        } else {
            gateTaken = false
        }

        do {
            try await purchasesService.send(transaction, userId: userId, options: options, trigger: .purchase)
            purchaseAssociationsStorage.remove(for: product.storeId)
        } catch {
            if gateTaken, let id: String = transaction.id {
                reportsGate.release(id)
            }
            // Deliberate: an unreachable backend still yields a successful
            // purchase, and the transaction stays unfinished for a re-report.
            if error.allowsLocalEntitlementsFallback {
                let entitlements: [String: Qonversion.Entitlement] = await entitlementsManager.localFallbackEntitlements(for: [transaction])
                return Qonversion.PurchaseResult(transaction: transaction, entitlements: entitlements, entitlementsSource: .localCalculation)
            }
            throw QonversionError(type: .purchaseReportingFailed, message: nil, error: error)
        }

        // Finish strictly after the backend ack, and only when the SDK owns
        // the lifecycle — in Analytics mode the host app does.
        if launchModeProvider.launchMode == .subscriptionManagement {
            await storeKitFacade.finish(transaction)
        }

        return await purchaseResult(for: transaction)
    }

    /// A reported purchase must not fail because of the entitlements fetch —
    /// and the caller is told which of the two answered.
    private func purchaseResult(for transaction: Qonversion.Transaction) async -> Qonversion.PurchaseResult {
        if let resolved: ResolvedEntitlements = try? await entitlementsManager.resolvedEntitlements() {
            return Qonversion.PurchaseResult(transaction: transaction, entitlements: resolved.entitlements, entitlementsSource: resolved.source)
        }

        let entitlements: [String: Qonversion.Entitlement] = await entitlementsManager.localFallbackEntitlements(for: [transaction])

        return Qonversion.PurchaseResult(transaction: transaction, entitlements: entitlements, entitlementsSource: .localCalculation)
    }

    @discardableResult
    func restore() async throws -> [String: Qonversion.Entitlement] {
        // Concurrent restore() calls join one run instead of syncing twice.
        let task: Task<[String: Qonversion.Entitlement], Error> = joinedRestoreTask()

        return try await task.value
    }

    func joinedRestoreTask() -> Task<[String: Qonversion.Entitlement], Error> {
        restoreTaskLock.lock()
        defer { restoreTaskLock.unlock() }

        if let inFlight: Task<[String: Qonversion.Entitlement], Error> = restoreTask {
            return inFlight
        }

        // The run releases the slot itself, or a joining call would get a
        // finished run's entitlements without the store sync restore() promises.
        // No identity check: nothing empties this slot out of band — add one
        // the moment anything else starts writing to `restoreTask`.
        let task = Task { [weak self] () throws -> [String: Qonversion.Entitlement] in
            guard let self else { return [:] }
            defer { self.clearRestoreTask() }

            return try await self.performRestore()
        }
        restoreTask = task

        return task
    }

    private func clearRestoreTask() {
        restoreTaskLock.lock()
        defer { restoreTaskLock.unlock() }
        restoreTask = nil
    }

    private func performRestore() async throws -> [String: Qonversion.Entitlement] {
        _ = try await userManager.obtainUser()
        let userId: String = userIdProvider.getUserId()

        let restored: [Qonversion.Transaction]
        do {
            restored = try await storeKitFacade.restore()
        } catch {
            // A store failure (e.g. a Stripe-only user without an Apple
            // receipt) must not discard the entitlements the backend knows.
            if let fetched: [String: Qonversion.Entitlement] = try? await entitlementsManager.entitlements(), !fetched.isEmpty {
                logger.warning("Store restore failed, returning backend entitlements: " + error.message)
                return fetched
            }
            // restore() is public: whatever the injected store layer raised,
            // the host must be able to classify it as a QonversionError.
            throw StoreKitPurchaseOutcome.storeError(error, fallbackType: .restoreFailed)
        }
        // Production rule: only the latest transaction per product participates.
        let latest = EntitlementsCalculator.latestTransactionsPerProduct(restored)

        var resolvedOwnerUserId: String?
        do {
            for transaction in latest {
                // Skip transactions already reported this session (sweep,
                // listener or purchase); the failed report releases the id.
                if let id: String = transaction.id {
                    guard reportsGate.tryTake(id) else { continue }
                }
                do {
                    let ownerUserId: String? = try await purchasesService.send(transaction, userId: userId, trigger: .restore)
                    if let ownerUserId, ownerUserId != userId {
                        resolvedOwnerUserId = ownerUserId
                    }
                } catch {
                    if let id: String = transaction.id {
                        reportsGate.release(id)
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

        await switchToOwnerIfNeeded(resolvedOwnerUserId)

        if let fetched: [String: Qonversion.Entitlement] = try? await entitlementsManager.entitlements() {
            return fetched
        }
        return await entitlementsManager.localFallbackEntitlements(for: latest)
    }

    /// The restored transactions may belong to another Qonversion user — the
    /// backend resolves the owner and the SDK follows (production parity).
    private func switchToOwnerIfNeeded(_ ownerUserId: String?) async {
        guard let ownerUserId else { return }

        do {
            try await userManager.switchToUser(with: ownerUserId)
        } catch {
            logger.error("Failed to switch to the transactions owner: " + error.message)
        }
    }

    func promotionalOffer(for product: Qonversion.Product, discountId: String) async throws -> Qonversion.PromotionalOffer {
        _ = try await userManager.obtainUser()
        let userId: String = userIdProvider.getUserId()

        return try await purchasesService.promotionalOffer(userId: userId, offerId: discountId, productStoreId: product.storeId)
    }

    /// Associations of the original SDK-initiated purchase of this product,
    /// if the report has not delivered them yet.
    private func reportOptions(for transaction: Qonversion.Transaction) -> Qonversion.PurchaseOptions? {
        guard let associations: PurchaseAssociations = purchaseAssociationsStorage.associations(for: transaction.productId) else { return nil }

        return Qonversion.PurchaseOptions(contextKeys: associations.contextKeys, screenUid: associations.screenUid)
    }

    #if os(iOS) || os(visionOS)
    func presentCodeRedemptionSheet() {
        storeKitFacade.presentCodeRedemptionSheet()
    }

    @available(iOS 16.0, *)
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await storeKitFacade.presentOfferCodeRedeemSheet(in: scene)
    }
    #endif

    #if os(visionOS)
    @MainActor
    func setPurchaseConfirmationScene(_ scene: UIScene?) {
        storeKitFacade.setPurchaseConfirmationScene(scene)
    }
    #endif

    func startObservingTransactions() {
        storeKitFacade.startObservingTransactionUpdates()
    }

    @discardableResult
    func handle(purchasedTransactions: [VerificationResult<StoreKit.Transaction>]) async -> Bool {
        let transactions: [Qonversion.Transaction] = purchasedTransactions.compactMap { storeKitFacade.map($0) }
        // Unverified results are dropped by the mapping — that is a failure
        // signal for the caller, not a silent success.
        let allVerified: Bool = transactions.count == purchasedTransactions.count

        let allReported: Bool = await handle(transactions: transactions)
        return allReported && allVerified
    }

    @discardableResult
    func handle(transactions: [Qonversion.Transaction]) async -> Bool {
        guard !transactions.isEmpty else { return true }

        let userId: String
        do {
            _ = try await userManager.obtainUser()
            userId = userIdProvider.getUserId()
        } catch {
            logger.error("Skipping handed transactions: no backend user: " + error.message)
            return false
        }

        // The host app made these purchases and owns their lifecycle — the
        // SDK only tracks them, so no transaction is ever finished here.
        var allReported = true
        for transaction in transactions {
            if let id: String = transaction.id {
                guard reportsGate.tryTake(id) else { continue }
            }
            do {
                try await purchasesService.send(transaction, userId: userId, trigger: .handleStoreKit2Transactions)
            } catch {
                if let id: String = transaction.id {
                    reportsGate.release(id)
                }
                allReported = false
                logger.error("Failed to report a handed transaction: " + error.message)
            }
        }
        return allReported
    }

    func syncHistoricalData() async {
        // Once per install, like the production SDK; a failed attempt stays
        // retriable on the next call.
        guard !localStorage.bool(forKey: Constants.historicalDataSyncedKey.rawValue) else { return }

        let userId: String
        do {
            _ = try await userManager.obtainUser()
            userId = userIdProvider.getUserId()
        } catch {
            logger.error("Skipping historical data sync: no backend user: " + error.message)
            return
        }

        // Transaction.all, deliberately WITHOUT AppStore.sync(): a background
        // sync must never trigger the App Store sign-in prompt.
        let history: [Qonversion.Transaction]
        do {
            history = try await storeKitFacade.historicalData()
        } catch {
            logger.error("Failed to fetch historical transactions: " + error.message)
            return
        }

        let latest: [Qonversion.Transaction] = EntitlementsCalculator.latestTransactionsPerProduct(history)

        var hadFailures = false
        var resolvedOwnerUserId: String?
        for transaction in latest {
            if let id: String = transaction.id {
                guard reportsGate.tryTake(id) else { continue }
            }
            do {
                let ownerUserId: String? = try await purchasesService.send(transaction, userId: userId, trigger: .syncHistoricalData)
                if let ownerUserId, ownerUserId != userId {
                    resolvedOwnerUserId = ownerUserId
                }
            } catch {
                if let id: String = transaction.id {
                    reportsGate.release(id)
                }
                hadFailures = true
                logger.error("Failed to report a historical transaction: " + error.message)
            }
        }

        await switchToOwnerIfNeeded(resolvedOwnerUserId)

        if !hadFailures {
            localStorage.set(bool: true, forKey: Constants.historicalDataSyncedKey.rawValue)
        }
    }

    func processUnfinishedTransactions() async {
        // Both modes re-report; only subscription management may FINISH
        // afterwards — in Analytics mode the host app owns the lifecycle.
        let finishAfterReport: Bool = launchModeProvider.launchMode == .subscriptionManagement

        let transactions: [Qonversion.Transaction] = await storeKitFacade.unfinishedTransactions()
        guard !transactions.isEmpty else { return }

        let userId: String
        do {
            _ = try await userManager.obtainUser()
            userId = userIdProvider.getUserId()
        } catch {
            logger.error("Skipping unfinished transactions: no backend user: " + error.message)
            return
        }

        for transaction in transactions {
            if let id: String = transaction.id {
                guard reportsGate.tryTake(id) else { continue }
            }
            do {
                try await purchasesService.send(transaction, userId: userId, options: reportOptions(for: transaction), trigger: .initialization)
                purchaseAssociationsStorage.remove(for: transaction.productId)
                if finishAfterReport {
                    await storeKitFacade.finish(transaction)
                }
            } catch {
                if let id: String = transaction.id {
                    reportsGate.release(id)
                }
                logger.error("Failed to re-report an unfinished transaction: " + error.message)
            }
        }
    }
}

// MARK: - UserChangedObserver

extension PurchasesManager: UserChangedObserver {

    var userChangeTeardownPriority: Int { UserChangeTeardownPriority.purchaseBookkeeping }

    func userDidChange() {
        // The reported-ids gate belongs to the previous user. Synchronous, so
        // it is ordered before any call following the user switch.
        reportsGate.reset()
    }
}

// MARK: - StoreKitFacadeDelegate

extension PurchasesManager: StoreKitFacadeDelegate {

    #if !os(watchOS) && !os(tvOS) && !os(visionOS)
    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) {
        emitPromoPurchaseIntent(storeProductId: product.id)
    }
    #endif

    /// The intent keys off the store product id, so no Qonversion product
    /// mapping is required.
    func emitPromoPurchaseIntent(storeProductId: String) {
        let intent: Qonversion.PromoPurchaseIntent = Qonversion.PromoPurchaseIntent(productId: storeProductId) { [weak self] options in
            guard let self else { throw QonversionError.initializationError() }

            return try await self.purchase(Qonversion.Product(qonversionId: storeProductId, storeId: storeProductId, offeringId: nil), options: options)
        }

        promoIntentsMulticast.yield(intent)
    }

    func transactionUpdated(_ transaction: Qonversion.Transaction) {
        // The host is notified in BOTH modes; only the lifecycle differs — in
        // Analytics mode the app owns it, otherwise the SDK finishes it.
        Task { [weak self] in
            guard let self else { return }

            // A purchase() call owns this product's lifecycle. Step aside
            // BEFORE reporting or finishing: a skipped transaction must stay
            // unfinished so the store re-delivers it.
            guard !self.isPurchasing(transaction.productId) else { return }

            // Transactions without a store id (degraded SK1 mapping) cannot be
            // deduplicated and are reported unconditionally.
            if let id: String = transaction.id {
                guard self.reportsGate.tryTake(id) else { return }
            }

            var reportFailed = false
            do {
                _ = try await self.userManager.obtainUser()
                let userId: String = self.userIdProvider.getUserId()
                try await self.purchasesService.send(transaction, userId: userId, options: self.reportOptions(for: transaction), trigger: .purchase)
                self.purchaseAssociationsStorage.remove(for: transaction.productId)
            } catch {
                if let id: String = transaction.id {
                    self.reportsGate.release(id)
                }
                self.logger.error("Failed to report an observed transaction: " + error.message)
                // An unreachable backend must not swallow the update; a
                // rejected report stays silent.
                guard error.allowsLocalEntitlementsFallback else { return }

                reportFailed = true
            }

            // Only a reported transaction may be finished, and only when the
            // SDK owns the lifecycle.
            if !reportFailed && self.launchModeProvider.launchMode == .subscriptionManagement {
                await self.storeKitFacade.finish(transaction)
            }

            // Gates what the host sees, not the report: a relaunch re-delivers
            // every unfinished transaction, and the host must hear it once.
            if let id: String = transaction.id, !self.markSurfacedIfNew(id) { return }

            let deferredPurchase: Qonversion.DeferredPurchase = await self.deferredPurchase(for: transaction, reportFailed: reportFailed)
            self.deferredPurchasesMulticast.yield(deferredPurchase)
        }
    }

    /// The source comes from the entitlements manager, never inferred from the
    /// absence of an error — its fallback path also answers successfully.
    private func deferredPurchase(for transaction: Qonversion.Transaction, reportFailed: Bool) async -> Qonversion.DeferredPurchase {
        if !reportFailed, let resolved: ResolvedEntitlements = try? await entitlementsManager.resolvedEntitlements() {
            return Qonversion.DeferredPurchase(transaction: transaction, entitlements: resolved.entitlements, entitlementsSource: resolved.source)
        }

        let calculated: [String: Qonversion.Entitlement] = await entitlementsManager.localFallbackEntitlements(for: [transaction])

        return Qonversion.DeferredPurchase(transaction: transaction, entitlements: calculated, entitlementsSource: .localCalculation)
    }
}
