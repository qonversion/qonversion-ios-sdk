# Migrating from the Objective-C SDK (5.x / 6.x)

This SDK is a full Swift rewrite with an async/await-first API. Existing installs migrate automatically — the stored Qonversion user id is picked up on the first launch of the new version, so your users keep their identity, purchases and entitlements. No data migration code is needed.

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+ / visionOS 1.0+ (previously iOS 9)
- Swift Package Manager only — CocoaPods and Carthage are not supported anymore
- Purchases run natively on StoreKit 2; StoreKit 1 is not used
- App Store promoted purchases surface via `promoPurchaseIntents` on iOS 16.4+ (a known gap on iOS 15.0–16.3)

## API mapping

Every completion-handler API became `async`. Errors are thrown instead of passed to callbacks.

| Objective-C SDK | Swift SDK |
|---|---|
| `Qonversion.initWithConfig(configuration)` | `Qonversion.initialize(with: configuration)` |
| `identify(userID)` / `identify(userID, completion)` | `try await identify(userID)` |
| `logout()` | `await logout()` — await it before the next `identify` |
| `userInfo(completion)` | `try await userInfo()` |
| `products(completion)` | `try await products()` |
| `purchaseWithResult(product, options, completion)` | `try await purchase(product, options: options)` |
| `restore(completion)` | `try await restore()` |
| `checkEntitlements(completion)` | `try await checkEntitlements()` |
| `checkTrialIntroEligibility(productIds, completion)` | `try await checkTrialIntroEligibility(productIds)` |
| `getPromotionalOfferForProduct(product, discount, completion)` | `try await getPromotionalOffer(for: product, discountId: discountId)` |
| `syncHistoricalData()` | `syncHistoricalData()` — unchanged, still once per install |
| `setDeferredPurchasesListener(listener)` | `for await entitlements in Qonversion.shared.entitlementsUpdates { ... }` |
| `setEntitlementsUpdateListener(listener)` *(deprecated)* | same stream: `entitlementsUpdates` |
| `setPromoPurchasesDelegate(delegate)` | `for await intent in Qonversion.shared.promoPurchaseIntents { try await intent.purchase() }` |
| `handlePurchases([QONStoreKit2PurchaseModel], completion)` | `await handlePurchases([VerificationResult<Transaction>]) -> Bool` — pass StoreKit 2 results directly; the returned flag replaces the completion |
| `setUserProperty(key, value)` / `setCustomUserProperty` | unchanged (plus the new `.tenjinAnalyticsInstallationId` key) |
| `userProperties(completion)` | `try await userProperties()` |
| `forceSendProperties(completion)` | `await forceSendProperties()` |
| `collectAppleSearchAdsAttribution()` / `collectAdvertisingId()` | unchanged |
| `remoteConfig(...)` / `remoteConfigList(...)` | `try await remoteConfig(contextKey:)` / `try await remoteConfigList(...)` |
| `attachUserToExperiment` / `detach...` / `...RemoteConfiguration` | unchanged, `async throws` |
| `presentCodeRedemptionSheet()` | unchanged; plus `presentOfferCodeRedeemSheet(in:)` on iOS 16+ |
| `isFallbackFileAccessible()` | unchanged |

### Listeners became streams

Delegate/listener protocols are gone. Both streams follow the style of StoreKit's `Transaction.updates`: every access returns an independent stream, subscribe from as many places as you need, and promo purchase intents arriving before your first subscription are buffered.

```swift
// before: conforming to QONDeferredPurchasesListener
Task {
    for await entitlements in Qonversion.shared.entitlementsUpdates {
        refreshUI(with: entitlements)
    }
}

// before: conforming to QONPromoPurchasesDelegate
Task {
    for await intent in Qonversion.shared.promoPurchaseIntents {
        let result = try await intent.purchase()   // now, or keep the intent for later
    }
}
```

### Errors

`NSError` with `QONErrorCode` became the thrown `QonversionError` with a typed `type`:

```swift
do {
    let result = try await Qonversion.shared.purchase(product)
} catch let error as QonversionError {
    switch error.type {
    case .purchaseCancelled: break            // the user changed their mind — not a failure
    case .purchasePending: break              // Ask to Buy / SCA: completes later via entitlementsUpdates
    default: showError(error.message)         // error.error carries the underlying failure
    }
}
```

### Purchase result

`purchase` returns `PurchaseResult` with the verified store `transaction` and the resulting `entitlements`. The transaction is finished only after Qonversion confirms the purchase; when Qonversion is unreachable, the purchase still succeeds with locally calculated entitlements and the report is retried automatically.

## Removed APIs

| API | Replacement |
|---|---|
| `offerings(completion)` | Removed — offerings are deprecated product-wide. Manage paywall products with [Remote Configs](https://documentation.qonversion.io/docs/migrate-offerings-to-remote-configs). |
| `purchase(productID, completion)` and other deprecated purchase variants | `purchase(_:options:)` with a `Qonversion.Product` |
| `attribution(data, fromProvider)` | Removed — was already a deprecated no-op; attribution works automatically |
| `setNotificationsToken` / `handleNotification` | Removed — were deprecated automation APIs |
| `launchMode` implicit default | `Configuration(apiKey:launchMode:)` requires an explicit mode |

## Fallback file

The bundled fallback file keeps the same name (`qonversion_ios_fallbacks.json`) and shape: `products`, `products_permissions` and `remote_config_list` are honored when the API is unreachable and no cache exists yet.

## NoCodes and Web2App

The NoCodes screens and Web2App redemption flow are not part of this SDK yet. If you rely on them, stay on the Objective-C SDK for now.
