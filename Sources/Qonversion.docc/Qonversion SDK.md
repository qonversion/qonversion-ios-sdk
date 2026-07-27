# Getting Started

Set up the SDK and make the first purchase.

## Initialize

Initialize the SDK as early as possible on app launch. Pick the launch mode by who owns the purchase flow: `.subscriptionManagement` when the SDK processes purchases and finishes transactions, `.analytics` when your own StoreKit code stays in charge and Qonversion only tracks revenue.

```swift
import Qonversion

let configuration = Qonversion.Configuration(
    apiKey: "YOUR_PROJECT_KEY",          // Qonversion Dashboard → Settings
    launchMode: .subscriptionManagement
)
Qonversion.initialize(with: configuration)
```

## Sell and unlock

```swift
let products = try await Qonversion.shared.products()
let result = try await Qonversion.shared.purchase(products[0])

let entitlements = try await Qonversion.shared.checkEntitlements()
if entitlements["premium"]?.active == true {
    // unlock the feature
}
```

## Listen for updates

Renewals, Ask to Buy approvals and purchases on other devices arrive out of band:

```swift
Task {
    for await purchase in Qonversion.shared.deferredPurchases {
        // the transaction and the resulting entitlements
        refreshUI(with: purchase.entitlements)
    }
}
```

For the complete guide — identity, promo offers, offline behavior, properties and remote config — see the README of the repository and the [official documentation](https://documentation.qonversion.io).
