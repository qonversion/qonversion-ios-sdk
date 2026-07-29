//
//  EntitlementsCalculator.swift
//  Qonversion
//
//  Local entitlements calculation — the fault-tolerance path used when the
//  backend is unreachable (5xx / connection errors). Mirrors the production
//  SDK logic exactly, including the deliberate day-based period approximation
//  (month = 30 days, year = 365 days).
//

import Foundation

extension Error {

    /// Production rule: entitlements may be calculated locally only for
    /// server (5xx) and connection errors — never for validation or auth
    /// failures.
    var allowsLocalEntitlementsFallback: Bool {
        if self is URLError { return true }
        guard let qonversionError = self as? QonversionError else { return false }
        if qonversionError.type == .internal { return true }
        // Named explicitly, so a copy built without the underlying URLError
        // still keeps the offline fallback.
        if qonversionError.type == .networkConnectionFailed { return true }
        if let underlying = qonversionError.error {
            return underlying.allowsLocalEntitlementsFallback
        }
        return false
    }
}

enum EntitlementsCalculator {

    /// Approximate period length in days, exactly as production does it.
    static func periodDays(_ period: Qonversion.Product.SubscriptionPeriod) -> Int {
        let days: Int
        switch period.unit {
        case .day:
            days = 1
        case .week:
            days = 7
        case .month:
            days = 30
        case .year:
            days = 365
        default:
            days = 1
        }

        return days * period.value
    }

    /// Expiration for a transaction of the given product: purchase date plus
    /// the approximated subscription period; nil when the product carries no
    /// subscription period (lifetime / consumable / product unknown).
    static func expirationDate(for transaction: Qonversion.Transaction, product: Qonversion.Product?) -> Date? {
        // The Apple-signed expiration is authoritative: a 7-day trial on an
        // annual product expires in 7 days, not in the approximated 365.
        if let signedExpiration: Date = transaction.expirationDate {
            return signedExpiration
        }

        guard let period = product?.subscription?.subscriptionPeriod else { return nil }

        let startDate: Date = transaction.purchaseDate ?? Date()
        return startDate.addingTimeInterval(TimeInterval(periodDays(period) * 24 * 60 * 60))
    }

    /// The date access really ends: a subscription whose renewal payment failed
    /// keeps it through a billing grace period, past the expiration its last
    /// paid transaction carries. A nil expiration is a lifetime grant and has
    /// nothing to extend.
    static func extended(_ expiration: Date?, byGracePeriod graceExpiration: Date?) -> Date? {
        guard let expiration else { return nil }
        guard let graceExpiration, graceExpiration > expiration else { return expiration }

        return graceExpiration
    }

    /// Builds entitlements from local transactions, the loaded products and
    /// the cached product → permissions mapping.
    ///
    /// Grant rule (production-exact): an entitlement is granted when the
    /// calculated expiration is nil (lifetime) or in the future; expired
    /// transactions are skipped entirely. A revoked transaction (refund,
    /// family-sharing revocation) grants nothing at all — a grace period does
    /// not rescue it either, since the purchase itself was undone.
    ///
    /// `gracePeriodExpirations` maps a STORE product id to the date the store
    /// keeps serving it while a failed renewal is retried.
    static func calculate(
        transactions: [Qonversion.Transaction],
        products: [Qonversion.Product],
        mapping: [String: [String]],
        gracePeriodExpirations: [String: Date] = [:],
        now: Date = Date()
    ) -> [String: Qonversion.Entitlement] {
        var productsByStoreId: [String: Qonversion.Product] = [:]
        for product in products where !product.storeId.isEmpty {
            productsByStoreId[product.storeId] = product
        }

        var result: [String: Qonversion.Entitlement] = [:]
        for transaction in transactions {
            // Checked before the expiration: a refunded lifetime purchase has
            // no expiration to fail, and a mid-period refund has one in the future.
            guard transaction.revocationDate == nil else { continue }

            let product: Qonversion.Product? = productsByStoreId[transaction.productId]
            let paidExpiration: Date? = expirationDate(for: transaction, product: product)
            let expiration: Date? = extended(paidExpiration, byGracePeriod: gracePeriodExpirations[transaction.productId])
            guard expiration == nil || expiration! > now else { continue }

            guard let qonversionId = product?.qonversionId,
                  let permissionIds: [String] = mapping[qonversionId] else { continue }

            for permissionId in permissionIds {
                let entitlement = Qonversion.Entitlement(
                    id: permissionId,
                    active: true,
                    source: .appStore,
                    startedDate: transaction.purchaseDate,
                    expirationDate: expiration,
                    productId: qonversionId
                )
                // Several products may grant the same permission: the longest
                // access wins, no matter in which order the store returned
                // the transactions.
                if let existing = result[permissionId], !outlasts(entitlement, existing) { continue }

                result[permissionId] = entitlement
            }
        }

        return result
    }

    /// The entitlement ids the given revoked transactions used to grant.
    ///
    /// A refund is not something the local calculation can express — it simply
    /// stops producing the entitlement — so a copy persisted before the refund
    /// would outlive it in the merge. These ids are what that merge must drop.
    static func revokedEntitlementIds(
        revokedTransactions: [Qonversion.Transaction],
        products: [Qonversion.Product],
        mapping: [String: [String]]
    ) -> Set<String> {
        var productsByStoreId: [String: Qonversion.Product] = [:]
        for product in products where !product.storeId.isEmpty {
            productsByStoreId[product.storeId] = product
        }

        var result: Set<String> = []
        for transaction in revokedTransactions where transaction.revocationDate != nil {
            guard let qonversionId: String = productsByStoreId[transaction.productId]?.qonversionId,
                  let permissionIds: [String] = mapping[qonversionId] else { continue }

            result.formUnion(permissionIds)
        }

        return result
    }

    /// Whether the candidate grants access at least as long as the current
    /// one: a nil expiration is a lifetime grant and outlasts any date.
    static func outlasts(_ candidate: Qonversion.Entitlement, _ current: Qonversion.Entitlement) -> Bool {
        switch (candidate.expirationDate, current.expirationDate) {
        case (nil, _):
            return true
        case (_, nil):
            return false
        case (let candidateDate?, let currentDate?):
            return candidateDate > currentDate
        }
    }

    /// Merges locally calculated entitlements on top of the current ones
    /// (production rule): a calculated entitlement replaces the existing one
    /// only when there is none, the existing one is inactive, or the new one
    /// expires later.
    static func merge(
        _ calculated: [String: Qonversion.Entitlement],
        into existing: [String: Qonversion.Entitlement]
    ) -> [String: Qonversion.Entitlement] {
        var result: [String: Qonversion.Entitlement] = existing

        for entitlement in calculated.values {
            guard let current = result[entitlement.id] else {
                result[entitlement.id] = entitlement
                continue
            }
            if !current.active || outlasts(entitlement, current) {
                result[entitlement.id] = entitlement
            }
        }

        return result
    }

    /// Restore variant (production-exact): keep only the LATEST transaction
    /// per store product before calculating.
    static func latestTransactionsPerProduct(_ transactions: [Qonversion.Transaction]) -> [Qonversion.Transaction] {
        let sorted: [Qonversion.Transaction] = transactions.sorted {
            ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast)
        }

        var seen = Set<String>()
        var result: [Qonversion.Transaction] = []
        for transaction in sorted where !seen.contains(transaction.productId) {
            seen.insert(transaction.productId)
            result.append(transaction)
        }

        return result
    }
}
