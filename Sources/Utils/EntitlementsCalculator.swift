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
        guard let period = product?.subscription?.subscriptionPeriod else { return nil }

        let startDate: Date = transaction.purchaseDate ?? Date()
        return startDate.addingTimeInterval(TimeInterval(periodDays(period) * 24 * 60 * 60))
    }

    /// Builds entitlements from local transactions, the loaded products and
    /// the cached product → permissions mapping.
    ///
    /// Grant rule (production-exact): an entitlement is granted when the
    /// calculated expiration is nil (lifetime) or in the future; expired
    /// transactions are skipped entirely.
    static func calculate(
        transactions: [Qonversion.Transaction],
        products: [Qonversion.Product],
        mapping: [String: [String]],
        now: Date = Date()
    ) -> [String: Qonversion.Entitlement] {
        var productsByStoreId: [String: Qonversion.Product] = [:]
        for product in products where !product.storeId.isEmpty {
            productsByStoreId[product.storeId] = product
        }

        var result: [String: Qonversion.Entitlement] = [:]
        for transaction in transactions {
            let product: Qonversion.Product? = productsByStoreId[transaction.productId]
            let expiration: Date? = expirationDate(for: transaction, product: product)
            guard expiration == nil || expiration! > now else { continue }

            guard let qonversionId = product?.qonversionId,
                  let permissionIds: [String] = mapping[qonversionId] else { continue }

            for permissionId in permissionIds {
                result[permissionId] = Qonversion.Entitlement(
                    id: permissionId,
                    active: true,
                    source: .appStore,
                    startedDate: transaction.purchaseDate,
                    expirationDate: expiration,
                    productId: qonversionId
                )
            }
        }

        return result
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
            let expiresLater: Bool
            switch (entitlement.expirationDate, current.expirationDate) {
            case (nil, _):
                expiresLater = true
            case (_, nil):
                expiresLater = false
            case (let new?, let old?):
                expiresLater = new > old
            }
            if !current.active || expiresLater {
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
