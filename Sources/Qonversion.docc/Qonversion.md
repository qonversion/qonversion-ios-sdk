# ``Qonversion``

In-app subscription monetization: implement subscriptions and grow your app's revenue with A/B experiments.

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

## Overview

``Qonversion/Qonversion`` is the entry point of the SDK. Initialize it once on app launch, then use ``Qonversion/Qonversion/shared`` for every call:

```swift
let configuration = Qonversion.Configuration(
    apiKey: "YOUR_PROJECT_KEY",
    launchMode: .subscriptionManagement
)
Qonversion.initialize(with: configuration)

let products = try await Qonversion.shared.products()
let result = try await Qonversion.shared.purchase(products[0])
```

The API is async/await-first. Purchases run natively on StoreKit 2; transactions are finished only after Qonversion confirms the purchase, and entitlements keep working through backend outages via the on-device fallback.

## Topics

### Initialization

- ``Qonversion/Qonversion/initialize(with:)``
- ``Qonversion/Qonversion/shared``
- ``Qonversion/Qonversion/Configuration``
- ``Qonversion/Qonversion/LaunchMode``
- ``Qonversion/Qonversion/Environment``

### User identity

- ``Qonversion/Qonversion/identify(_:)``
- ``Qonversion/Qonversion/logout()``
- ``Qonversion/Qonversion/userInfo()``
- ``Qonversion/Qonversion/User``

### Products and purchases

- ``Qonversion/Qonversion/products()``
- ``Qonversion/Qonversion/purchase(_:options:)``
- ``Qonversion/Qonversion/getPromotionalOffer(for:discountId:)``
- ``Qonversion/Qonversion/checkTrialIntroEligibility(_:)``
- ``Qonversion/Qonversion/restore()``
- ``Qonversion/Qonversion/syncHistoricalData()``
- ``Qonversion/Qonversion/Product``
- ``Qonversion/Qonversion/PurchaseOptions``
- ``Qonversion/Qonversion/PurchaseResult``
- ``Qonversion/Qonversion/EntitlementsSource``
- ``Qonversion/Qonversion/setPurchaseConfirmationScene(_:)``

### Entitlements

- ``Qonversion/Qonversion/checkEntitlements()``
- ``Qonversion/Qonversion/deferredPurchases``
- ``Qonversion/Qonversion/DeferredPurchase``
- ``Qonversion/Qonversion/entitlementsUpdates``
- ``Qonversion/Qonversion/Entitlement``
- ``Qonversion/Qonversion/isFallbackFileAccessible()``

### Promoted purchases

- ``Qonversion/Qonversion/promoPurchaseIntents``
- ``Qonversion/Qonversion/PromoPurchaseIntent``

### Analytics mode

- ``Qonversion/Qonversion/handlePurchases(_:)``

### User properties and attribution

- ``Qonversion/Qonversion/setUserProperty(_:key:)``
- ``Qonversion/Qonversion/setCustomUserProperty(_:key:)``
- ``Qonversion/Qonversion/userProperties()``
- ``Qonversion/Qonversion/forceSendProperties()``
- ``Qonversion/Qonversion/collectAppleSearchAdsAttribution()``
- ``Qonversion/Qonversion/collectAdvertisingId()``

### Remote config

- ``Qonversion/Qonversion/remoteConfig(contextKey:)``
- ``Qonversion/Qonversion/remoteConfigList()``
- ``Qonversion/Qonversion/remoteConfigList(contextKeys:includeEmptyContextKey:)``
- ``Qonversion/Qonversion/RemoteConfig``

### Errors

Every SDK call throws ``QonversionError``. Switch on ``QonversionError/type``
to react precisely; when the failure came from the API, ``QonversionError/apiCode``
carries the backend code verbatim (a snake_case slug such as `relation_not_found`
or `purchase_fraud`) and ``QonversionError/apiType`` its class — `internal`,
`logical`, `request` or `resource`. A code the SDK has no typed meaning for
leaves ``QonversionError/type`` derived from the HTTP status and still reaches
you through ``QonversionError/apiCode``.

- ``QonversionError``
- ``QonversionErrorType``
