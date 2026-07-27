# Migrating from the Objective-C SDK (5.x / 6.x)

This SDK is a full Swift rewrite with an async/await-first API. Existing installs migrate automatically — the stored Qonversion user id is picked up on the first launch of the new version, so your users keep their identity, purchases and entitlements. No data migration code is needed.

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+ / visionOS 1.0+ (previously iOS 9)
- Swift Package Manager only — CocoaPods and Carthage are not supported anymore
- Purchases run natively on StoreKit 2; StoreKit 1 is not used
- App Store promoted purchases surface via `promoPurchaseIntents` on iOS 16.4+ and macOS 14.4+ (a known gap on iOS 15.0–16.3). StoreKit declares `PurchaseIntent` unavailable on watchOS, tvOS and visionOS, so there the stream exists but finishes immediately — a `for await` over it is safe and returns at once
- On visionOS, call `setPurchaseConfirmationScene(_:)` before purchasing — see [visionOS purchases](#visionos-purchases)

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
| `setDeferredPurchasesListener(listener)` | `for await purchase in Qonversion.shared.deferredPurchases { ... }` |
| `setEntitlementsUpdateListener(listener)` *(deprecated)* | `entitlementsUpdates` — the entitlements-only projection of the same stream |
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
| `QONEnvironment` on the configuration | `Configuration(apiKey:launchMode:environment:)` — the same two values, `.production` by default. The environment travels in the user creation body; the `test_` API key prefix of the older API is not used. |

### Listeners became streams

Delegate/listener protocols are gone. Both streams follow the style of StoreKit's `Transaction.updates`: every access returns an independent stream, subscribe from as many places as you need, and promo purchase intents arriving before your first subscription are buffered.

```swift
// before: conforming to QONDeferredPurchasesListener
Task {
    for await purchase in Qonversion.shared.deferredPurchases {
        // purchase.transaction and purchase.entitlements, like QONPurchaseResult;
        // purchase.entitlementsSource tells whether the backend answered or
        // the SDK calculated them locally
        refreshUI(with: purchase.entitlements)
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
    case .purchasePending: break              // Ask to Buy / SCA: completes later via deferredPurchases
    default: showError(error.message)         // error.error carries the underlying failure
    }
}
```

The numeric `QONErrorCode` is gone. What the backend answered is still available
unfiltered on `error.apiCode` (a snake_case slug) and `error.apiType`
(`internal` | `logical` | `request` | `resource`, absent on the `/v4/web`
surface), so handling more specific than `type` stays possible.

`type` is derived from the HTTP status and then refined by the backend code.
The refinement never overrides the two classifications the SDK acts on itself:
401/402/403 stay `.critical` (they latch the revoked-key stop) and 5xx stays
`.internal` (it drives the offline entitlements fallback).

These are the backend codes that map to a type of their own; anything else
keeps the status-derived type and reaches you as `apiCode`:

| Backend code | `QonversionErrorType` |
|---|---|
| `invalid_data`, `invalid_request`, `validation_error`, `invalid_entitlement_data` | `.invalidRequest` |
| `not_found`, `relation_not_found`, `user_not_found` | `.resourceNotFound` |
| `too_many_requests`, `rate_limit_exceeded` | `.rateLimitExceeded` |
| `purchase_fraud` | `.fraudPurchase` |
| `store_not_configured`, `store_creds_failed`, `token_not_found`, `secrets_not_found`, `settings_not_found` | `.projectConfigError` |
| `subscription_period_parse_error`, `apple_purchase_type_error`, `conflicting_purchase_found` | `.receiptValidationError` |

`.paymentNotAllowed` and `.storeProductNotAvailable` have no backend code — they
come from StoreKit failures (parental controls, a product missing from the
current storefront).

### visionOS purchases

visionOS has no scene-less StoreKit purchase call: the system needs to know
which of the app's scenes the purchase sheet belongs to. Name it once, the same
way `presentOfferCodeRedeemSheet(in:)` takes a scene:

```swift
Qonversion.initialize(with: configuration)

// visionOS only — the method does not exist on other platforms
Qonversion.shared.setPurchaseConfirmationScene(windowScene)

let result = try await Qonversion.shared.purchase(product)
```

Call it **after `Qonversion.initialize(with:)`** and before the first
`purchase(_:options:)`, and update it when the scene your paywall lives in
changes. Calling it before `initialize` drops the scene and logs a warning.
The scene is held weakly, so a discarded scene is not kept alive. Purchasing
without one throws a `QonversionError` of type `.purchaseSceneMissing` instead
of crashing. Nothing changes on iOS, macOS, tvOS or watchOS.

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

## User fields

`Qonversion.User` exposes `originalAppVersion` — the app version the user
originally downloaded from the App Store, for grandfathering older installs.

## Purchase and deferred purchase provenance

`PurchaseResult` and `DeferredPurchase` both carry `entitlementsSource`
(`.backend` / `.localCalculation`), so an integrator can tell an answer the
Qonversion backend confirmed from one the SDK computed on the device while the
backend was unreachable.

## Entitlement fields

`Qonversion.Entitlement` exposes the same information as `QONEntitlement`: next
to `id`, `active`, `source`, `renewState`, `startedDate`, `expirationDate` and
`productId` it carries `grantType`, `renewsCount`, `trialStartDate`,
`firstPurchaseDate`, `lastPurchaseDate`, `autoRenewDisableDate`,
`lastActivatedOfferCode` and `transactions`.

`transactions` is a list of `Qonversion.Entitlement.StoreTransaction` — the
billing history records behind the entitlement (`QONTransaction` in the
Objective-C SDK). The StoreKit wrapper returned by purchases keeps its own
name, `Qonversion.Transaction`.

Every one of these fields is optional on the wire: an older backend that does
not send them yet yields the defaults (`grantType == .purchase`,
`renewsCount == 0`, nil dates, an empty `transactions` list).

### `renewState` and non-renewable products

The API answers `will_renew`, `canceled` or `billing_issue` — and nothing else.
A non-renewable purchase (a consumable, a lifetime product) is expressed by
sending **no subscription object at all**, so `.nonRenewable` is derived, using
the backend's own rule: no renew state on a non-manual source means
non-renewable; on a manual grant there is no store subscription to report a
state for, so it stays `.unknown`.

`QONRenewState` in the Objective-C SDK had the same five cases, so switch
statements port unchanged — only where `.nonRenewable` comes from differs.

## Fallback file

The bundled fallback file keeps the same name (`qonversion_ios_fallbacks.json`) and shape: `products`, `products_permissions` and `remote_config_list` are honored when the API is unreachable and no cache exists yet.

## NoCodes and Web2App

The NoCodes screens and Web2App redemption flow are not part of this SDK yet. If you rely on them, stay on the Objective-C SDK for now.

## Offline purchase queue of the Objective-C SDK

The previous SDK kept failed purchase reports in its own UserDefaults suite as
archived `NSURLRequest`s. Those requests target the previous API, so they
cannot be replayed against v4, and the transaction ids they are keyed by are
not enough to rebuild a v4 report. The SDK therefore drops that key on the
first launch.

No purchase is lost by this: the Objective-C SDK never finished a transaction
whose report had failed, so those purchases are still unfinished in StoreKit
and the SDK re-reports them on the first launch (and `syncHistoricalData()`
covers the rest of the history once per install).
