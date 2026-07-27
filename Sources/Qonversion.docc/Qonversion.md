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

The API is async/await-first. Purchases run on StoreKit 2 (iOS 15+) with an automatic StoreKit 1 fallback; transactions are finished only after Qonversion confirms the purchase, and entitlements keep working through backend outages via the on-device fallback.

## Topics

### Initialization

- ``Qonversion/Qonversion/initialize(with:)``
- ``Qonversion/Qonversion/shared``
- ``Qonversion/Qonversion/Configuration``
- ``Qonversion/Qonversion/LaunchMode``

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

### Entitlements

- ``Qonversion/Qonversion/checkEntitlements()``
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

- ``QonversionError``
- ``QonversionErrorType``
