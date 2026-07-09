<h1 align="center">
    Qonversion
</h1>

Qonversion - In-app subscription monetization: implement subscriptions and grow your app’s revenue with A/B experiments 

* In-app subscription management SDK
* API and webhooks to make your subscription data available where you need it
* Seamless Stripe integration to enable cross-platform access management
* Subscribers CRM with user-level transactions
* Instant access to real-time subscription analytics
* Built-in A/B experiments for subscription business model

<p align="center">
     <a href="https://qonversion.io"><img width="90%" src="https://qcdn3.sfo3.digitaloceanspaces.com/github/qonversion_platform.png">
     </a>
</p>

[![SPM Compatible](https://img.shields.io/badge/SPM-compatible-green.svg?style=flat)](https://documentation.qonversion.io/docs/ios-sdk-setup)
[![Release](https://img.shields.io/github/v/release/qonversion/qonversion-ios-sdk?style=flat)](https://github.com/qonversion/qonversion-ios-sdk/releases)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat)](https://qonversion.io)

## Getting Started

### Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Purchases run on StoreKit 2 (iOS 15+) with an automatic StoreKit 1 fallback on older systems
- The public API is async/await-first

### Installation

The SDK is distributed via Swift Package Manager only. In Xcode: **File → Add Package Dependencies…** and paste:

```
https://github.com/qonversion/qonversion-ios-sdk
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/qonversion/qonversion-ios-sdk", from: "6.0.0")
]
```

### Initialization

Initialize the SDK once, as early as possible on app launch:

```swift
import Qonversion

let configuration = Qonversion.Configuration(
    apiKey: "YOUR_PROJECT_KEY",          // Qonversion Dashboard → Settings
    launchMode: .subscriptionManagement
)
Qonversion.initialize(with: configuration)
```

Pick the launch mode by who owns the purchase flow:

| Mode | Who processes purchases | Who finishes transactions |
|---|---|---|
| `.subscriptionManagement` | The SDK (`purchase`, `restore`) | The SDK, strictly after Qonversion confirms the purchase |
| `.analytics` | Your own StoreKit code | Your app — the SDK only tracks (`handlePurchases`) and never finishes anything |

Optional configuration:

```swift
Qonversion.Configuration(
    apiKey: "YOUR_PROJECT_KEY",
    launchMode: .subscriptionManagement,
    proxyURL: "your.proxy.domain",             // route API traffic through your server
    entitlementsCacheLifetime: .month,         // how long cached entitlements power the offline fallback
    logLevel: .warning                         // .verbose ... .disabled
)
```

### User identity

Every install gets an anonymous Qonversion user. Link it to your own user id after sign-in — if the id is already linked to another Qonversion user, the SDK switches to that user and invalidates every user-scoped cache:

```swift
try await Qonversion.shared.identify("your_user_id")

await Qonversion.shared.logout()   // back to a fresh anonymous user; await it before the next identify

let user = try await Qonversion.shared.userInfo()
```

Installs updated from the previous production SDK keep their user automatically — the stored uid is migrated on first launch.

### Products and purchases

```swift
let products = try await Qonversion.shared.products()

let result = try await Qonversion.shared.purchase(products[0])
// result.transaction — the verified store transaction
// result.entitlements — the user's access after the purchase
```

The transaction is finished **only after Qonversion confirms the purchase**. If the backend is unreachable, the purchase still succeeds with locally calculated entitlements, and the report is retried automatically (offline queue + a sweep of unfinished transactions on the next launch).

Attach context to a purchase — quantity, the remote config context and the screen that initiated it:

```swift
let options = Qonversion.PurchaseOptions(quantity: 1, contextKeys: ["main_paywall"], screenUid: "scr_42")
try await Qonversion.shared.purchase(product, options: options)
```

Promotional offers are signed by Qonversion:

```swift
let offer = try await Qonversion.shared.getPromotionalOffer(for: product, discountId: "promo_id")
try await Qonversion.shared.purchase(product, options: Qonversion.PurchaseOptions(promoOffer: offer))
```

Restore and history:

```swift
let entitlements = try await Qonversion.shared.restore()

Qonversion.shared.syncHistoricalData()   // once per install; call it on the first launch of the integrated build
```

### Entitlements

```swift
let entitlements = try await Qonversion.shared.checkEntitlements()
if entitlements["premium"]?.active == true {
    // unlock the feature
}
```

When Qonversion is unreachable (5xx / connection issues), entitlements are calculated locally from StoreKit data with the production-grade rules and the persisted cache — purchases and restores never fail because of a temporary outage. For the very first launch without a network connection, bundle a fallback file `qonversion_ios_fallbacks.json` with your products and entitlement definitions.

### Update streams

Both streams follow the style of StoreKit's `Transaction.updates`: every access returns an independent stream, so subscribe from as many places as you need.

Entitlements refreshed by out-of-band transactions — Ask to Buy approvals, renewals, purchases on other devices (subscription-management mode):

```swift
for await entitlements in Qonversion.shared.entitlementsUpdates {
    // refresh the UI
}
```

Purchases promoted in the App Store — call `purchase()` right away or keep the intent and trigger it when the app is ready (e.g. after onboarding); intents arriving before your subscription are buffered:

```swift
for await intent in Qonversion.shared.promoPurchaseIntents {
    try await intent.purchase()
}
```

### Analytics mode

Report the purchases your own StoreKit 2 code makes, so Qonversion can track them. The SDK never finishes these transactions — your app owns their lifecycle:

```swift
let result = try await product.purchase()
if case .success(let verificationResult) = result {
    await Qonversion.shared.handlePurchases([verificationResult])
}
```

### User properties and attribution

```swift
Qonversion.shared.setUserProperty("test@example.com", key: .email)
Qonversion.shared.setCustomUserProperty("value", key: "my_key")
let properties = try await Qonversion.shared.userProperties()

Qonversion.shared.collectAppleSearchAdsAttribution()
Qonversion.shared.collectAdvertisingId()   // after the ATT permission is granted
```

### Sample

The `Sample` scheme in `Qonversion.xcodeproj` is a working demo of every flow above — set your project key in `AppDelegate` and run.

## In-App Subscription Implementation & Management

<p align="center">
     <a href="https://documentation.qonversion.io/docs/integrations-overview"><img width="90%" src="https://user-images.githubusercontent.com/13959241/161107203-8ef3ecee-86be-47a2-ac57-b21d3da19339.png">
     </a>
</p>

1. Qonversion SDK provides three simple methods to manage subscriptions:
	* Get in-app product details
	* Make purchases
	* Check subscription status to manage premium access
2. Qonversion communicates with Apple or Google platforms both through SDK and server-side to process native in-app payments and keep subscription statuses up to date.
3. You can use Qonversion webhooks and API in addition to SDK to get user-level data where you need it.

See the [quick start guide documentation](https://documentation.qonversion.io/docs/quickstart).

## Analytics

Qonversion provides advanced subscription analytics out-of-the-box. You can monitor real-time metrics from new users and trial-to-paid conversions to revenue, MRR, ARR, cohort retention and more. Understand your customers and make better decisions with precise subscription analytics.

<p align="center">
     <a href="https://documentation.qonversion.io/docs/analytics"><img width="90%" src="https://files.readme.io/9a4fdf6-Analytics.png">
     </a>
</p>


## A/B Experiments

Qonversion's A/B Experiments feature provides everything required to quickly launch paywall and other monetization experiments, analyze results and roll out winning versions without releasing a new app build. Qonversion A/B Experiments include:

* User segmentation by country, install date, app version, free/paying user
* Traffic allocation
* Advanced subscription analytics
* Visualization of A/B experiments results
* Statistical significance of the results
* Roll out winning versions without app release with remote config


<p align="center">
     <a href="https://documentation.qonversion.io/docs/subscription-ab-testing"><img width="90%" src="https://qcdn3.sfo3.digitaloceanspaces.com/github/ab_tests.png">
     </a>
</p>

See more details [here](https://documentation.qonversion.io/docs/paywall-experiments).

## Integrations

Send user-level subscription data to your favorite platforms.

* Amplitude
* Mixpanel
* Appsflyer
* Adjust
* Singular
* CleverTap
* [All other integrations here](qonversion.io/integrations)

<p align="center">
     <a href="https://documentation.qonversion.io/docs/integrations-overview"><img width="90%", src="https://qcdn3.sfo3.digitaloceanspaces.com/github/integrations.png">
     </a>
</p>

## Why Qonversion?

* **No headaches with Apple's StoreKit & Google Billing.** Qonversion provides simple methods to handle Apple StoreKit & Google Billing purchase flow.
* **Receipt validation.** Qonversion validates user receipts with Apple and Google to provide 100% accurate purchase information and subscription statuses. It also prevents unauthorized access to the premium features of your app.
* **Track and increase your revenue.** Qonversion provides detailed real-time revenue analytics including cohort analysis, trial conversion rates, country segmentation, and much more.
* **Integrations with the leading mobile platforms.** Qonversion allows sending data to platforms like AppsFlyer, Adjust, Branch, Tenjin, Facebook Ads, Amplitude, Mixpanel, and many others.
* **Change promoted in-app products.** Change promoted in-app products anytime without app releases.
* **A/B test** and identify winning in-app purchases, subscriptions or paywals.
* **Cross-device and cross-platform access management.** If you provide user authorization in your app, you can easily set Qonversion to provide premium access to authorized users across devices and operating systems.
* **SDK caches the data.** Qonversion SDK caches purchase data including in-app products and entitlements, so the user experience is not affected even with the slow or interrupting network connection.
* **Webhooks.** You can easily send all of the data to your server with Qonversion webhooks.
* **Customer support.** You can always reach out to our customer support and get the help required.

Convinced? Let's go!

## Documentation

Check the [full documentation](https://documentation.qonversion.io/docs/quickstart) to learn about implementation details and available features.

#### Help us improve the documentation

Whether you’re a core user or trying it out for the first time, you can make a valuable contribution to Qonversion by improving the documentation. Help us by:

* sending us feedback about something you thought was confusing or simply missing
* sending us a pull request via GitHub
* suggesting better wording or ways of explaining certain topics in the [Qonversion documentation](http://documentation.qonversion.io). Use `SUGGEST EDITS` button in the top right corner.

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/SuperFeature`)
3. Commit your Changes. Use small commits with separate logic. (`git commit -m 'Add some super feature'`)
4. Push to the Branch (`git push origin feature/SuperFeature`)
5. Open a Pull Request


## Have a question?

Contact us via [issues on GitHub](https://github.com/qonversion/qonversion-ios-sdk/issues) or [ask a question](https://documentation.qonversion.io/discuss-new) on the site.

## License

Qonversion SDK is available under the MIT license.
