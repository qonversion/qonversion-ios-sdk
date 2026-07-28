# Migrating from the Objective-C SDK (5.x / 6.x)

This SDK is a full Swift rewrite with an async/await-first API. Existing installs migrate automatically — the stored Qonversion user id is picked up on the first launch of the new version, so your users keep their identity, purchases and entitlements. No data migration code is needed.

On that first launch the SDK also carries over the Objective-C SDK's local
caches: the cached entitlements (with their sources, renew states, dates and
store transactions) and the product → entitlements mapping. That mapping is
what powers the offline local entitlement calculation, so a user who updates
the app and opens it without a network keeps their access instead of losing it
until the first successful request. The old keys are consumed once read.

The one thing that is NOT carried over is the previous SDK's offline purchase
queue: those requests target the previous API and cannot be replayed. Nothing
is lost — that SDK never finished a transaction whose report had failed, so the
unfinished-transaction sweep re-reports them in v4 form.

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
| `setUserProperty:value:` / `setCustomUserProperty:value:` | `setUserProperty(key:value:)` / `setCustomUserProperty(key:value:)` — same key-first order as Objective-C, plus the new `.tenjinAnalyticsInstallationId` key |
| `userProperties(completion)` | `try await userProperties()` |
| `forceSendProperties(completion)` | `await forceSendProperties()` |
| `collectAppleSearchAdsAttribution()` / `collectAdvertisingId()` | unchanged |
| `remoteConfig(...)` / `remoteConfigList(...)` | `try await remoteConfig(contextKey:)` / `try await remoteConfigList(...)` |
| `attachUserToExperiment` / `detach...` / `...RemoteConfiguration` | unchanged, `async throws` |
| `presentCodeRedemptionSheet()` | unchanged; plus `presentOfferCodeRedeemSheet(in:)` on iOS 16+ |
| `isFallbackFileAccessible()` | unchanged |
| `QONEnvironment` on the configuration | Removed — see [The environment flag is gone](#the-environment-flag-is-gone). |

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

`.networkConnectionFailed` also has no backend code: it means the request never
reached the backend at all (a connection-class `URLError` after the transport
retries were exhausted). The legacy SDK surfaced these as raw `NSURLError`s;
here the underlying failure stays available on `error.error`. A response that
arrived but could not be read remains `.invalidResponse`.

One mapping is contextual: on the remote config endpoints `not_found` and
`relation_not_found` mean *this user (or this context key) has no
configuration*, not "the SDK asked for something that does not exist". There
they become `.remoteConfigurationNotAvailable` — the counterpart of the ObjC
SDK's `QONErrorCodeRemoteConfigurationNotAvailable`. Everywhere else the 404
family stays `.resourceNotFound`.

A load abandoned because the SDK switched users (a logout, or an identify that
resolved to another user) fails with `.cancelled` rather than a bare
`CancellationError` — the call is safe to repeat once the switch is done.

`userInfo()` answers from the persisted user record when the network fetch
fails, like the Objective-C SDK always did; it throws only when there is no
user at all.

Remote config failures are no longer flattened into
`.loadingRemoteConfigFailed`: a classified backend failure reaches you with its
own `type`, `apiCode` and `apiType`. `.loadingRemoteConfigFailed` and
`.loadingRemoteConfigListFailed` are now what they say — the failure could not
be classified.

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
| `QONEnvironment` / `environment:` on the configuration | Removed — see below |

### The environment flag is gone

The Objective-C SDK carried a sandbox marker — `QONEnvironment` on the
configuration — and sent it with every request; the Swift rewrite additionally
put it in the user creation body. Neither exists any more: this SDK sends no
environment marker at all, and `Configuration` has no `environment` parameter.
Drop the argument from your `Configuration(...)` call; there is nothing to pass
in its place.

The marker was a host-declared claim about the build, not an observed fact, so
it was wrong whenever a host forgot to flip it — a `.sandbox` value shipped to
the App Store labelled real production data as test data. Removing it means the
SDK no longer makes that claim on your behalf.

If environment separation is needed later, it will be reintroduced deliberately,
with a backend contract behind it. Until then, do not expect the backend to
split your data by build type on the SDK's word.

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

A product row's App Store id may be spelled `store_id` (what the Objective-C
SDK read, and what the files already in your bundle use) or `apple_product_id`
(the spelling of the `/v4/products` API). `store_id` wins when both are
present, so an unmodified file from the previous SDK generation keeps working.

Every section and every row is read independently: a malformed product row is
skipped instead of discarding the file, and a broken `products` section no
longer takes `products_permissions` and `remote_config_list` down with it.

## SDK crash reporting

The Objective-C SDK installed an uncaught-exception handler and captured
exceptions whose stack ran through Qonversion (`QONExceptionManager`). That is
back, with the same scope — **NSException only**, no signal handlers, no Mach
exception ports, so it never competes with the crash reporter your app already
uses — and the handler that was installed before it is always called
afterwards.

What changed: the queue of pending reports is hard-bounded (five, oldest
dropped) instead of unbounded files in the app's Documents directory, and the
whole call stack is scanned instead of stopping at the first app frame.

Nothing is sent for your app's own crashes; a stack with no Qonversion frame is
ignored.

## IDFA and the Kids Category

**Action required only if your app collects the advertising identifier.**

The Objective-C SDK linked `AdSupport`, the advertising *identifier* framework,
so every app that integrated it carried the reference — which is why the
`Qonversion/NoIdfa` subspec existed as an opt-*out* for Kids Category apps and
anyone else declaring no tracking.

This SDK never links `AdSupport`. Nothing in the binary references it, and there
is no separate product or build flag to pick: **kids apps need to do nothing at
all**, and the `NoIdfa` subspec has no successor because it no longer has a job.

`AdServices` is a different framework and is still linked — it is what
`collectAppleSearchAdsAttribution()` reads the Apple Search Ads attribution
token through, and it exposes no advertising identifier.

Linking is now the opt-*in*, and it lives in your app instead of in the SDK. If
your app collects the identifier, add the framework to your own target:

- **Xcode:** target → *General* → *Frameworks, Libraries, and Embedded Content*
  → **+** → `AdSupport.framework`.
- **Swift Package Manager:** add `.linkedFramework("AdSupport")` to your
  target's `linkerSettings`.

The SDK picks the framework up at run time and reads the identifier through it.
No API changed: `collectAdvertisingId()` keeps its signature and its meaning,
the identifier still respects App Tracking Transparency, and the SDK still
reports none when the user has not granted the permission. The only difference
is that with the framework absent the identifier is simply never available —
silently, with no error and no crash.

| Objective-C SDK | Swift SDK |
|---|---|
| `pod 'Qonversion'` linked the advertising framework for you | Never linked — link it in your app target if you want the identifier |
| `pod 'Qonversion/NoIdfa'` to opt out | Removed — not linking is the default |
| `collectAdvertisingId()` | Unchanged; a no-op when your app does not link `AdSupport` |
| The identifier also became the `_q_advertising_id` user property | Removed — it travels in the device record only (`advertisingId`) |

### The identifier is no longer a user property

**Action required if you read the IDFA back out of Qonversion, or feed user
properties into another system.**

`collectAdvertisingId()` used to do two things: attach the identifier to the
device record *and* set it as the `_q_advertising_id` user property. It now
attaches it to the device record only, under the wire key `advertisingId`. The
signature and the meaning of the call are unchanged — this is about where the
value lands.

The identifier is device data, and it was being stored twice, in two places
with two lifetimes, from one call. The device record is the one that belongs to
it.

What you feel:

- `userProperties()` no longer returns `_q_advertising_id`.
- Integrations fed from user properties no longer receive the identifier
  through Qonversion. If one of yours relies on it, send it from your app.

`Qonversion.UserPropertyKey.advertisingId` still exists, so an app that wants
the old behavior can set the property itself with
`setUserProperty(key: .advertisingId, value:)` — the SDK just no longer does it
for you.

### One knock-on effect: the Facebook anonymous id

If your app integrates the Facebook SDK, the rule is unchanged in principle —
the anonymous id is collected **exactly when no usable IDFA exists** — but which
apps that covers has widened. Previously "no usable IDFA" meant the user had
denied tracking; now it also covers every app that does not link `AdSupport`.
So a host app without the framework will start sending `facebook_anon_id` on the
wire where it previously sent an IDFA instead. Link `AdSupport` if you want the
old split back; there is nothing to change in your code either way.

## NoCodes

NoCodes screens are part of this SDK, as a separate `NoCodes` library in the same package — add it to your app target next to `Qonversion` and `import NoCodes`. In the Objective-C SDK the module was compiled into the main framework, so the only integration change is the extra product and import.

No-Codes is an iOS-only feature. The library resolves on the other platforms so a multi-platform package can depend on it unconditionally, but it exposes no entry point there — keep the calls behind `#if os(iOS)`.

The API kept its shape: `NoCodes.initialize(with: NoCodesConfiguration(projectKey:))`, `showScreen(withContextKey:)`, `loadScreen(withContextKey:)`, `close()`, `setLocale(_:)`, `setTheme(_:)` and the `NoCodesDelegate` / `NoCodesScreenCustomizationDelegate` / `NoCodesCustomVariablesDelegate` / `NoCodesPurchaseDelegate` set. The differences to expect:

| Objective-C SDK | Swift SDK |
|---|---|
| `showScreen(with id:)` *(deprecated)* | Removed — screens are addressed by their context key: `showScreen(withContextKey:)` |
| `NoCodesScreenCustomizationDelegate.presentationConfigurationForScreen(id:)` | Removed together with the id-based entry point that used to call it. Configure the presentation in `presentationConfigurationForScreen(contextKey:)`; screens opened by an in-chain navigation action keep the configuration of the screen that opened them. |
| Delegates retained by the SDK | Held **weakly**, like any UIKit delegate. All four protocols are class-bound now (`AnyObject`), so keep your own strong reference — a delegate created inline and passed to `NoCodesConfiguration` is released immediately and the callbacks stop arriving. |
| `import NoCodes` re-exported the main SDK | Import both: `import Qonversion` is required wherever you touch `Qonversion.Product` (for example in a `NoCodesPurchaseDelegate` implementation) — the `@_exported` import is gone now that NoCodes is its own module. |
| `noCodesFailedToExecute(action:error:)` had no working default | The protocol declared `noCodesFailedToExecute(action:error:)` while the default implementation was written for `noCodesFailedToExecute(action:)` — a different selector, so it never satisfied the requirement and every host had to implement the method. The default now matches the declared signature, like every other `NoCodesDelegate` method. The flip side: a misspelled signature compiles and silently loses the callbacks — the exact signature is `func noCodesFailedToExecute(action: NoCodesAction, error: Error?)`. |
| Facade and delegates callable from any thread | Main-actor isolated: they present and hand out UIKit objects, so call them from the main actor and mark your delegate implementations `@MainActor`. `NoCodesConfiguration` is main-actor isolated too. |

The bundled fallback file keeps the same name (`nocodes_fallbacks.json`) and shape.

## Web2App

The Web2App redemption flow is not part of this SDK yet. If you rely on it, stay on the Objective-C SDK for now.

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
