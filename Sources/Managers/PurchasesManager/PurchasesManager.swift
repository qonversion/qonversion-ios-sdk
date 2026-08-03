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
    // A revocation carries the id of the purchase it undoes, which that set
    // already holds; this prefix gives it a namespace of its own.
    case revokedTransactionPrefix = "revoked:"
    // The transactions the backend refused for good, persisted: the store
    // re-delivers them forever, and every re-report gets the same refusal.
    case rejectedTransactionsKey = "qonversion.keys.rejectedTransactions"
}

fileprivate enum IntConstants {
    /// Bounds the surfaced-transactions set; the oldest ids are dropped first.
    static let maxSurfacedTransactions = 200
    /// Bounds the rejected-transactions set; the oldest ids are dropped first.
    static let maxRejectedTransactions = 200
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

    // Concurrent syncHistoricalData() calls must join one store read and one
    // set of backend reports.
    private let historicalSyncTaskLock = NSLock()
    private var historicalSyncTask: Task<Bool, Never>?
    private var historicalSyncGeneration = 0

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

    /// Takes the id for a path that reports a transaction but neither finishes
    /// nor surfaces it. Such a path hands the id straight back — as delivered
    /// when it posted the report, as free when it did not — so the path that
    /// owns the whole outcome can still take it. False means someone else is
    /// posting this transaction, or already has.
    private func claimForReport(_ id: String) -> Bool {
        guard reportsGate.tryTake(id) else { return false }
        guard !reportsGate.wasReported(id) else {
            reportsGate.markReported(id)
            return false
        }

        return true
    }

    // Guards the surfaced bookkeeping below.
    private let surfacedLock = NSLock()

    // Emitted for the host in this launch but not heard by it yet: the claim
    // keeps a second path from emitting the same transaction, the persisted
    // record is what survives a relaunch.
    private var claimedTransactions: Set<String> = []

    /// Ids the store still holds unfinished, refreshed by every launch sweep.
    /// They are exactly the deliveries that come back, so the surfaced set may
    /// not evict them to stay within its size bound.
    private var protectedTransactionIds: Set<String> = []

    private func protectUnfinished(_ transactionIds: [String]) {
        surfacedLock.lock()
        defer { surfacedLock.unlock() }

        protectedTransactionIds = Set(transactionIds)
    }

    /// Caller holds `surfacedLock`.
    private func isProtected(_ key: String) -> Bool {
        let prefix: String = Constants.revokedTransactionPrefix.rawValue
        let transactionId: String = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key

        return protectedTransactionIds.contains(transactionId)
    }

    /// Trims the surfaced set back to its bound by dropping the OLDEST ids the
    /// store can no longer re-deliver. An id it still holds unfinished survives
    /// even over the bound: in Analytics mode nothing is ever finished, so
    /// forgetting one repeats that purchase to the host on every launch from
    /// then on. Caller holds `surfacedLock`.
    private func withinBound(_ surfaced: [String]) -> [String] {
        var excess: Int = surfaced.count - IntConstants.maxSurfacedTransactions
        guard excess > 0 else { return surfaced }

        var result: [String] = []
        result.reserveCapacity(surfaced.count)
        for key in surfaced {
            if excess > 0, !isProtected(key) {
                excess -= 1
                continue
            }
            result.append(key)
        }

        return result
    }

    /// True when the host has not heard about this transaction yet — and
    /// claims it for this launch.
    private func claimForHost(_ transactionId: String) -> Bool {
        surfacedLock.lock()
        defer { surfacedLock.unlock() }

        let surfaced: [String] = storedSurfacedTransactions()
        guard !claimedTransactions.contains(transactionId), !surfaced.contains(transactionId) else { return false }

        claimedTransactions.insert(transactionId)

        return true
    }

    /// Records that the host actually received this transaction. Persisted:
    /// StoreKit re-delivers unfinished transactions on every launch, and
    /// Analytics mode never finishes any. Recording it only after the delivery
    /// is what brings an event nobody received back on the next launch.
    private func markHeardByHost(_ transactionId: String) {
        surfacedLock.lock()
        defer { surfacedLock.unlock() }

        claimedTransactions.insert(transactionId)
        var surfaced: [String] = storedSurfacedTransactions()
        guard !surfaced.contains(transactionId) else { return }

        surfaced.append(transactionId)
        try? localStorage.set(withinBound(surfaced), forKey: Constants.surfacedTransactionsKey.rawValue)
    }

    private func storedSurfacedTransactions() -> [String] {
        return (try? localStorage.object(forKey: Constants.surfacedTransactionsKey.rawValue, dataType: [String].self)) ?? []
    }

    /// Ids the SDK itself finished in this launch. The store re-delivers
    /// neither through the sweep nor through the updates listener, so nothing
    /// can produce their deliveries a second time.
    private var sdkFinishedTransactions: Set<String> = []

    private func recordSDKFinished(_ transactionId: String) {
        surfacedLock.lock()
        defer { surfacedLock.unlock() }

        sdkFinishedTransactions.insert(transactionId)
    }

    private func isFinishedBySDK(_ transactionId: String) -> Bool {
        surfacedLock.lock()
        defer { surfacedLock.unlock() }

        return sdkFinishedTransactions.contains(transactionId)
    }

    // Guards the rejected bookkeeping below.
    private let rejectedLock = NSLock()

    /// True when the backend refused this transaction in a way no repetition
    /// can change — a 4xx that is neither throttling nor a timeout.
    private func isRejectedTransaction(_ transactionId: String) -> Bool {
        rejectedLock.lock()
        defer { rejectedLock.unlock() }

        return storedRejectedTransactions().contains(transactionId)
    }

    private func recordRejectedTransaction(_ transactionId: String) {
        rejectedLock.lock()
        defer { rejectedLock.unlock() }

        var rejected: [String] = storedRejectedTransactions()
        guard !rejected.contains(transactionId) else { return }

        rejected.append(transactionId)
        let excess: Int = rejected.count - IntConstants.maxRejectedTransactions
        if excess > 0 {
            rejected.removeFirst(excess)
        }
        try? localStorage.set(rejected, forKey: Constants.rejectedTransactionsKey.rawValue)
    }

    private func clearRejectedTransactions() {
        rejectedLock.lock()
        defer { rejectedLock.unlock() }

        localStorage.removeObject(forKey: Constants.rejectedTransactionsKey.rawValue)
    }

    private func storedRejectedTransactions() -> [String] {
        return (try? localStorage.object(forKey: Constants.rejectedTransactionsKey.rawValue, dataType: [String].self)) ?? []
    }

    // An approval processed before the host subscribes waits with no deadline
    // and is handed to the first subscription only. Internal for the test that
    // asserts the deadline it must NOT have.
    let deferredPurchasesMulticast = AsyncMulticast<Qonversion.DeferredPurchase>(backlog: .deliveredOnce, backlogLifetime: .infinity)

    // Buffered until the first subscriber — an intent arriving at app start
    // must not be lost, and acting on the same one twice would purchase twice.
    // Internal for the test that asserts the deadline it must NOT have.
    let promoIntentsMulticast = AsyncMulticast<Qonversion.PromoPurchaseIntent>(backlog: .deliveredOnce, backlogLifetime: .infinity)

    // Snapshots, not events: a host that re-subscribes may read the latest
    // access state again. The single access-state channel — a revocation
    // carries no DeferredPurchase and reaches the host through this one.
    private let entitlementsMulticast = AsyncMulticast<[String: Qonversion.Entitlement]>(backlog: .replayed)

    func deferredPurchases() -> AsyncStream<Qonversion.DeferredPurchase> {
        return deferredPurchasesMulticast.stream()
    }

    /// The entitlements-only projection of the deferred purchases, plus the
    /// revocations no deferred purchase can carry. Fed alongside them rather
    /// than derived from a subscription, so reading it never takes a purchase
    /// away from ``deferredPurchases()``.
    func entitlementsUpdates() -> AsyncStream<[String: Qonversion.Entitlement]> {
        return entitlementsMulticast.stream()
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

        // The id is claimed BEFORE the report goes out: a concurrent restore
        // or sweep must not report the same transaction. A failed report
        // releases the id for retries.
        let gateTaken: Bool
        if let id: String = transaction.id {
            gateTaken = reportsGate.tryTake(id)
            // Another flow owns the report and will finish the transaction;
            // this call still answers with entitlements.
            guard gateTaken else {
                let result: Qonversion.PurchaseResult = await purchaseResult(for: transaction)

                return heard(result)
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
                let result = Qonversion.PurchaseResult(transaction: transaction, entitlements: entitlements, entitlementsSource: .localCalculation)

                return heard(result)
            }
            // Nothing is recorded as heard: the caller gets an exception, not a
            // result, so it never learned about this purchase.
            throw QonversionError(type: .purchaseReportingFailed, message: nil, error: error)
        }

        // The report changed what the backend knows: without this the result
        // is served from the pre-purchase fresh-cache window.
        entitlementsManager.invalidateFreshBackendCache()

        // Finish strictly after the backend ack, and only when the SDK owns
        // the lifecycle — in Analytics mode the host app does.
        if launchModeProvider.launchMode == .subscriptionManagement {
            await storeKitFacade.finish(transaction)
        }

        let result: Qonversion.PurchaseResult = await purchaseResult(for: transaction)

        return heard(result)
    }

    /// Records the purchase as delivered, on the paths that actually hand the
    /// host a result. A re-delivery through the updates listener must not
    /// repeat it as a deferred purchase — but a call that THREW told the host
    /// nothing, and the store's next delivery is its only way to learn.
    private func heard(_ result: Qonversion.PurchaseResult) -> Qonversion.PurchaseResult {
        if let id: String = result.transaction.id {
            markHeardByHost(id)
        }

        return result
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
        // A revocation is not a purchase, and it must not take its product's
        // slot away from the transaction that paid for it.
        let latest = EntitlementsCalculator.latestTransactionsPerProduct(restored.filter { $0.revocationDate == nil })

        var resolvedOwnerUserId: String?
        do {
            for transaction in latest {
                // Skip transactions already reported this session (sweep,
                // listener or purchase); the failed report releases the id.
                if let id: String = transaction.id {
                    guard claimForReport(id) else { continue }
                }
                do {
                    let ownerUserId: String? = try await purchasesService.send(transaction, userId: userId, trigger: .restore)
                    // Restore reports but neither finishes nor surfaces the
                    // transaction: the id goes back for the path that can.
                    if let id: String = transaction.id {
                        reportsGate.markReported(id)
                    }
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

        // The store sync reached the backend: the answer restore() returns
        // must not come from the window opened before it.
        entitlementsManager.invalidateFreshBackendCache()

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

    func promotionalOffer(for product: Qonversion.Product, discountId: String, appAccountToken: UUID?) async throws -> Qonversion.PromotionalOffer {
        // Eligibility is the backend's answer, decided on the purchase history
        // it already holds: it replies not_eligible when that history is not
        // enough. Uploading the store history first would neither be needed for
        // that answer nor be able to gate it — one permanently rejected report
        // would deny every signature from then on, and the paywall would wait
        // out a sequential network pass over the whole history.
        _ = try await userManager.obtainUser()
        let userId: String = userIdProvider.getUserId()

        return try await purchasesService.promotionalOffer(userId: userId, offerId: discountId, productStoreId: product.storeId, appAccountToken: appAccountToken)
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
                guard claimForReport(id) else { continue }
            }
            do {
                try await purchasesService.send(transaction, userId: userId, trigger: .handleStoreKit2Transactions)
                // Reported, but the host owns the lifecycle here: the id goes
                // back for the path that finishes and surfaces it.
                if let id: String = transaction.id {
                    reportsGate.markReported(id)
                }
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

    @discardableResult
    func syncHistoricalData() async -> Bool {
        // Once per install, like the production SDK; a failed attempt stays
        // retriable on the next call.
        guard !localStorage.bool(forKey: Constants.historicalDataSyncedKey.rawValue) else { return true }

        let operation = historicalSyncOperation()
        let result = await operation.task.value
        clearHistoricalSyncOperation(generation: operation.generation)
        return result
    }

    private func historicalSyncOperation() -> (task: Task<Bool, Never>, generation: Int) {
        historicalSyncTaskLock.lock()
        defer { historicalSyncTaskLock.unlock() }

        if let historicalSyncTask {
            return (historicalSyncTask, historicalSyncGeneration)
        }

        historicalSyncGeneration += 1
        let generation = historicalSyncGeneration
        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performHistoricalDataSync()
        }
        historicalSyncTask = task
        return (task, generation)
    }

    private func clearHistoricalSyncOperation(generation: Int) {
        historicalSyncTaskLock.lock()
        defer { historicalSyncTaskLock.unlock() }

        guard historicalSyncGeneration == generation else { return }
        historicalSyncTask = nil
    }

    /// The run in the slot was computed for the previous user: a call made
    /// after the switch must start its own instead of joining that one.
    private func invalidateHistoricalSyncOperation() {
        historicalSyncTaskLock.lock()
        defer { historicalSyncTaskLock.unlock() }

        historicalSyncGeneration += 1
        historicalSyncTask?.cancel()
        historicalSyncTask = nil
    }

    private func performHistoricalDataSync() async -> Bool {
        // A caller could have completed the once-per-install work immediately
        // before this operation acquired the single-flight slot.
        guard !localStorage.bool(forKey: Constants.historicalDataSyncedKey.rawValue) else { return true }

        let userId: String
        do {
            _ = try await userManager.obtainUser()
            userId = userIdProvider.getUserId()
        } catch {
            logger.error("Skipping historical data sync: no backend user: " + error.message)
            return false
        }

        let unverifiedBeforeFetch: Int = storeKitFacade.unverifiedTransactionsCount

        // Transaction.all, deliberately WITHOUT AppStore.sync(): a background
        // sync must never trigger the App Store sign-in prompt.
        let history: [Qonversion.Transaction]
        do {
            history = try await storeKitFacade.historicalData()
        } catch {
            logger.error("Failed to fetch historical transactions: " + error.message)
            return false
        }

        // A revocation is not a purchase, and it must not take its product's
        // slot away from the transaction that paid for it.
        let purchased: [Qonversion.Transaction] = history.filter { $0.revocationDate == nil }
        let latest: [Qonversion.Transaction] = EntitlementsCalculator.latestTransactionsPerProduct(purchased)

        // The local verification drops transactions for honest, temporary
        // reasons too (a rolled clock, a certificate rotation), so a fetch that
        // lost some of them has not synced the history.
        var hadFailures: Bool = storeKitFacade.unverifiedTransactionsCount > unverifiedBeforeFetch
        var reportedAny = false
        var skippedIds: [String] = []
        var resolvedOwnerUserId: String?
        for transaction in latest {
            if let id: String = transaction.id {
                guard claimForReport(id) else {
                    skippedIds.append(id)
                    continue
                }
            }
            do {
                let ownerUserId: String? = try await purchasesService.send(transaction, userId: userId, trigger: .syncHistoricalData)
                reportedAny = true
                // The sync neither finishes nor surfaces a transaction, so the
                // id goes back for the path that can, marked as delivered.
                if let id: String = transaction.id {
                    reportsGate.markReported(id)
                }
                if let ownerUserId, ownerUserId != userId {
                    resolvedOwnerUserId = ownerUserId
                }
            } catch {
                if let id: String = transaction.id {
                    reportsGate.release(id)
                }
                // Only a report that may yet succeed keeps the sync from
                // completing: a rejected one is rejected again on every launch,
                // and waiting for it would re-post the whole history forever.
                if !error.isRejectedByBackend {
                    hadFailures = true
                }
                logger.error("Failed to report a historical transaction: " + error.message)
            }
        }

        // Taking the id is not delivering the report: a holder that failed and
        // released it leaves the transaction unreported.
        if skippedIds.contains(where: { !reportsGate.wasReported($0) }) {
            hadFailures = true
        }

        // The uid moved while the reports were in flight — the owner switch and
        // the install-global flag belong to the session that started this run.
        guard userIdProvider.getUserId() == userId else { return false }

        await switchToOwnerIfNeeded(resolvedOwnerUserId)

        // The store sync reached the backend: the next answer must not come
        // from the window opened before it.
        if reportedAny {
            entitlementsManager.invalidateFreshBackendCache()
        }

        if !hadFailures {
            localStorage.set(bool: true, forKey: Constants.historicalDataSyncedKey.rawValue)
        }

        return !hadFailures
    }

    func processUnfinishedTransactions() async {
        let transactions: [Qonversion.Transaction] = await storeKitFacade.unfinishedTransactions()
        // The store's own answer to "what can still come back": whatever is in
        // it must survive in the surfaced set, however large that set gets.
        protectUnfinished(transactions.compactMap(\.id))
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
            await processObservedTransaction(transaction, userId: userId, trigger: .initialization)
        }
    }

    /// The single funnel for transactions the SDK did not purchase itself: the
    /// launch sweep and the updates listener race for the same deliveries, so
    /// whichever claims one produces the WHOLE outcome — report, finish per
    /// launch mode, one deferred purchase. A nil `userId` makes the funnel pass
    /// the user gate itself, and only once it owns the transaction.
    private func processObservedTransaction(_ transaction: Qonversion.Transaction, userId: String?, trigger: RequestTrigger) async {
        // Checked before every dedup gate below: a revocation arrives as the
        // very transaction the purchase already reported and surfaced, so both
        // gates hold its id and both would swallow it.
        if transaction.revocationDate != nil {
            await processRevocation(of: transaction)
            return
        }

        // A purchase() call owns this product's lifecycle. Step aside BEFORE
        // reporting or finishing: a skipped transaction must stay unfinished so
        // the store re-delivers it.
        guard !isPurchasing(transaction.productId) else { return }

        // Transactions without a store id (degraded SK1 mapping) cannot be
        // deduplicated and are reported unconditionally.
        if let id: String = transaction.id {
            // The backend refused this one for good in an earlier session: the
            // store keeps re-delivering it, the SDK must stop re-posting it.
            guard !isRejectedTransaction(id) else { return }
            guard reportsGate.tryTake(id) else { return }
        }

        let reportUserId: String
        if let userId {
            reportUserId = userId
        } else {
            do {
                _ = try await userManager.obtainUser()
                reportUserId = userIdProvider.getUserId()
            } catch {
                if let id: String = transaction.id {
                    reportsGate.release(id)
                }
                logger.error("Skipping an observed transaction: no backend user: " + error.message)
                return
            }
        }

        // The offline replay may have delivered this report already. It cannot
        // finish or surface a transaction, so the rest of the outcome is still
        // owed — only the POST must not happen twice.
        var alreadyReported = false
        if let id: String = transaction.id {
            alreadyReported = reportsGate.wasReported(id)
        }

        var reportFailed = false
        do {
            if !alreadyReported {
                try await purchasesService.send(transaction, userId: reportUserId, options: reportOptions(for: transaction), trigger: trigger)
                // The id stays taken, so a later path only learns from the gate
                // that this report was delivered, not that it was skipped.
                if let id: String = transaction.id {
                    reportsGate.markDelivered(id)
                }
            }
            purchaseAssociationsStorage.remove(for: transaction.productId)
            // The deferred purchase this delivery emits must carry the
            // entitlements the report produced, not the ones cached before it.
            entitlementsManager.invalidateFreshBackendCache()
        } catch {
            if let id: String = transaction.id {
                reportsGate.release(id)
            }
            logger.error("Failed to report an observed transaction: " + error.message)
            // An unreachable backend must not swallow the update; a rejected
            // report stays silent.
            guard error.allowsLocalEntitlementsFallback else {
                // Refused for good: record it so no later launch posts it
                // again, and finish it — an unfinished transaction is
                // re-delivered forever, and the report cannot succeed.
                if error.isRejectedByBackend, let id: String = transaction.id {
                    recordRejectedTransaction(id)
                    if launchModeProvider.launchMode == .subscriptionManagement {
                        await storeKitFacade.finish(transaction)
                    }
                }

                return
            }

            reportFailed = true
        }

        // Only a reported transaction may be finished, and only when the SDK
        // owns the lifecycle — in Analytics mode the host app does.
        if !reportFailed && launchModeProvider.launchMode == .subscriptionManagement {
            await storeKitFacade.finish(transaction)
            if let id: String = transaction.id {
                recordSDKFinished(id)
            }
        }

        // Gates what the host sees, not the report: a relaunch re-delivers
        // every unfinished transaction, and the host must hear it once.
        let transactionId: String? = transaction.id
        if let transactionId, !claimForHost(transactionId) { return }

        let deferredPurchase: Qonversion.DeferredPurchase = await self.deferredPurchase(for: transaction, reportFailed: reportFailed)
        // Marked heard only once it reaches a subscriber: an approval nobody
        // received must come back after the next launch.
        deferredPurchasesMulticast.yield(deferredPurchase) { [weak self] in
            guard let transactionId else { return }

            self?.markHeardByHost(transactionId)
        }
        entitlementsMulticast.yield(deferredPurchase.entitlements)
    }

    /// A refund or a family-sharing revocation. It is not a purchase: nothing
    /// is reported — the App Store server tells the backend about the refund —
    /// and no deferred purchase is emitted. The host learns about it from the
    /// recalculated entitlements published to ``entitlementsUpdates()``.
    private func processRevocation(of transaction: Qonversion.Transaction) async {
        // Finished before the dedup gate below: an unfinished revocation is
        // re-delivered on every launch. In Analytics mode the host app owns
        // the lifecycle, exactly as for a purchase.
        if launchModeProvider.launchMode == .subscriptionManagement {
            await storeKitFacade.finish(transaction)
        }

        if let id: String = transaction.id {
            let revocationKey: String = Constants.revokedTransactionPrefix.rawValue + id
            guard claimForHost(revocationKey) else { return }

            // Recorded right away rather than on delivery: the snapshot below
            // is state a later resolve reproduces, so a revocation nobody
            // heard has nothing to come back for.
            markHeardByHost(revocationKey)
        }

        // Whatever the fresh window holds was answered before the revocation.
        entitlementsManager.invalidateFreshBackendCache()

        let entitlements: [String: Qonversion.Entitlement]
        if let resolved: ResolvedEntitlements = try? await entitlementsManager.resolvedEntitlements() {
            entitlements = resolved.entitlements
        } else {
            entitlements = await entitlementsManager.localFallbackEntitlements(for: [transaction])
        }

        entitlementsMulticast.yield(entitlements)
    }
}

// MARK: - UserChangedObserver

extension PurchasesManager: UserChangedObserver {

    var userChangeTeardownPriority: Int { UserChangeTeardownPriority.purchaseBookkeeping }

    func userDidChange() {
        // The reported-ids gate belongs to the previous user. Synchronous, so
        // it is ordered before any call following the user switch.
        reportsGate.reset()
        invalidateHistoricalSyncOperation()

        // Whatever waits for a future subscriber describes the previous user:
        // an access snapshot is invalid the moment the uid moves.
        entitlementsMulticast.clearBacklog()

        // A deferred purchase nobody heard is not simply dropped — unclaiming
        // its transaction lets the funnel emit it again, with the entitlements
        // recalculated for the new user. One the SDK already finished has no
        // such second delivery, so it keeps waiting for a subscriber: the
        // purchase happened on this device whoever the user is now, and the
        // host reads where its entitlements came from off the event itself.
        let undelivered: [Qonversion.DeferredPurchase] = deferredPurchasesMulticast.clearBacklog()
        var redeliverable: [String] = []
        for purchase in undelivered {
            guard let transactionId: String = purchase.transaction.id else { continue }

            guard isFinishedBySDK(transactionId) else {
                redeliverable.append(transactionId)
                continue
            }

            deferredPurchasesMulticast.yield(purchase) { [weak self] in
                self?.markHeardByHost(transactionId)
            }
        }
        unclaim(redeliverable)

        // The refusals were answered for the previous user; the new one gets
        // its own attempt.
        clearRejectedTransactions()
    }

    private func unclaim(_ transactionIds: [String]) {
        guard !transactionIds.isEmpty else { return }

        surfacedLock.lock()
        defer { surfacedLock.unlock() }
        transactionIds.forEach { claimedTransactions.remove($0) }
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

            return try await self.purchase(Qonversion.Product(qonversionId: storeProductId, storeId: storeProductId), options: options)
        }

        promoIntentsMulticast.yield(intent)
    }

    func transactionUpdated(_ transaction: Qonversion.Transaction) {
        // The host is notified in BOTH modes; only the lifecycle differs — in
        // Analytics mode the app owns it, otherwise the SDK finishes it.
        Task { [weak self] in
            guard let self else { return }

            await self.processObservedTransaction(transaction, userId: nil, trigger: .purchase)
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
