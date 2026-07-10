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
- A Qonversion project: sign up at [qonversion.io](https://qonversion.io), create products and entitlements in the Dashboard, and grab the project key from **Settings**

### Core concepts

| Concept | What it is |
|---|---|
| **Product** | A Qonversion product linked to an App Store product. You operate Qonversion product ids in code, so changing the underlying store product doesn't require an app release. |
| **Entitlement** | The access level a purchase unlocks (e.g. `premium`). One entitlement can be unlocked by many products across platforms — an Apple subscription and a Stripe payment can grant the same access. Check entitlements, not receipts. |
| **Offering** | A group of products behind a paywall, in the display order configured in the Dashboard and personalized by A/B experiments. |
| **User** | Every install gets an anonymous Qonversion user; link it to your own user id with `identify`. Entitlements follow the user across devices and platforms. |

The flow: the app buys a store product → the SDK reports the purchase to Qonversion, which validates it with Apple → the user's entitlements update everywhere (device, other platforms, webhooks, integrations).

### Installation

The SDK is distributed via Swift Package Manager only.

In Xcode: **File → Add Package Dependencies…**, paste the repository URL and add the `Qonversion` library to your app target:

```
https://github.com/qonversion/qonversion-ios-sdk
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/qonversion/qonversion-ios-sdk", from: "6.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Qonversion", package: "qonversion-ios-sdk")
    ])
]
```

### Initialization

Initialize the SDK once, as early as possible on app launch — `application(_:didFinishLaunchingWithOptions:)` or your `App` initializer:

```swift
import Qonversion

let configuration = Qonversion.Configuration(
    apiKey: "YOUR_PROJECT_KEY",          // Qonversion Dashboard → Settings
    launchMode: .subscriptionManagement
)
Qonversion.initialize(with: configuration)
```

Initialization is synchronous and never blocks the launch. In the background it warms everything up: creates the backend user, refreshes the product → entitlements mapping, resumes purchase reports left unfinished by previous sessions, and starts observing out-of-band transactions (renewals, Ask to Buy approvals, purchases on other devices, offer code redemptions).

All configuration options:

```swift
let configuration = Qonversion.Configuration(
    apiKey: "YOUR_PROJECT_KEY",
    launchMode: .subscriptionManagement,
    proxyURL: "your.proxy.domain",       // optional
    entitlementsCacheLifetime: .month,   // default .month
    logLevel: .warning                   // default .verbose
)
```

| Option | What it does |
|---|---|
| `proxyURL` | Routes all SDK traffic through your server — for regions where the API domain may be unreachable. Contact Qonversion before using it. |
| `entitlementsCacheLifetime` | How long cached entitlements stay eligible for the offline fallback: `.week`, `.twoWeeks`, `.month`, `.twoMonths`, `.threeMonths`, `.sixMonths`, `.year`, `.unlimited`. |
| `logLevel` | Minimal severity written to the unified log: `.verbose`, `.debug`, `.warning`, `.error`, `.critical`, or `.disabled`. |

### Launch modes

Pick the mode by who owns the purchase flow — it defines who finishes StoreKit transactions, and finishing them twice or never are both bugs:

| | `.subscriptionManagement` | `.analytics` |
|---|---|---|
| Who calls StoreKit | The SDK (`purchase`, `restore`) | Your own code |
| Who finishes transactions | The SDK — strictly after Qonversion confirms the purchase | Your app; the SDK never touches them |
| How purchases reach Qonversion | Automatically | You pass them via `handlePurchases` |
| Out-of-band transactions (renewals, Ask to Buy, other devices) | The SDK reports **and finishes** them, then emits fresh entitlements into `entitlementsUpdates` | The SDK only observes; reporting is up to you |
| Entitlements | Calculated by Qonversion, with an on-device fallback | Available the same way |

Use `.subscriptionManagement` for a full integration where Qonversion is the source of truth for access. Use `.analytics` when you keep your existing StoreKit code and want revenue analytics, integrations, and the subscribers CRM on top of it.

### Users and identity

Every install starts as an anonymous Qonversion user (`QON_...`). After your own sign-in, link it:

```swift
let user = try await Qonversion.shared.identify("your_user_id")
```

Two outcomes, both handled for you:

- the id is new → it links to the current anonymous user, purchases made before sign-in stay with the account;
- the id is already linked to another Qonversion user (sign-in on a second device) → the SDK switches to that user and drops every user-scoped cache, so entitlements, offerings and remote configs are re-fetched for the right account.

```swift
await Qonversion.shared.logout()   // back to a fresh anonymous user; await it before the next identify

let user = try await Qonversion.shared.userInfo()
// user.id — the Qonversion user id (pass to support, find in the CRM)
// user.identityId — your id if the user is identified
```

Installs updated from the previous production SDK keep their Qonversion user automatically — the stored uid is migrated on first launch, no code needed.

### Products

```swift
let products = try await Qonversion.shared.products()
```

Products come enriched with App Store data, ready for a paywall:

```swift
for product in products {
    // Identity
    product.qonversionId       // "pro_monthly" — the id you operate in code
    product.storeId            // "com.app.pro.monthly" — the App Store product id

    // Display (localized by the store)
    product.displayName        // "Pro Monthly"
    product.displayPrice       // "$9.99"
    product.price              // Decimal(9.99)

    // Subscription details (nil for non-subscriptions)
    product.subscription?.subscriptionPeriod     // 1 month
    product.subscription?.introductoryOffer      // trial / intro price, if configured
    product.subscription?.promotionalOffers      // promo offers configured in App Store Connect

    // The raw store product, when you need the full StoreKit API
    product.storeProduct       // StoreKit.Product (iOS 15+)
    product.skProduct          // SKProduct (older systems)
}
```

### Offerings

Offerings are the recommended way to build paywalls: the set and order of products is controlled from the Dashboard and personalized by A/B experiments — no app release needed to change a paywall.

```swift
let offerings = try await Qonversion.shared.offerings()

if let main = offerings.main {                      // the offering marked as main
    show(products: main.products)                   // already in the paywall order
}
let onboarding = offerings.offering(for: "onboarding_paywall")
```

### Trial and intro eligibility

Show "Start your free trial" only to users who will actually get one. The check runs on the device via StoreKit 2 (subscription group history), no network round-trip:

```swift
let eligibility = try await Qonversion.shared.checkTrialIntroEligibility(["pro_monthly", "pro_annual"])

switch eligibility["pro_monthly"] {
case .eligible:                 break // show the trial CTA
case .ineligible:               break // trial already consumed — show the regular price
case .nonIntroOrTrialProduct:   break // no intro offer configured
case .unknown, .none:           break // store can't answer (e.g. iOS < 15)
}
```

### Making purchases

```swift
let products = try await Qonversion.shared.products()
let result = try await Qonversion.shared.purchase(products[0])

result.transaction                            // the verified store transaction
result.entitlements["premium"]?.active        // access right after the purchase
```

The transaction is finished **only after Qonversion confirms the purchase** — an unreported purchase is never lost. A user cancellation and a pending purchase (Ask to Buy, SCA) surface as errors; a pending purchase completes later through the out-of-band flow and arrives via `entitlementsUpdates`.

Attach context to a purchase:

```swift
let options = Qonversion.PurchaseOptions(
    quantity: 1,                       // consumables
    contextKeys: ["main_paywall"],     // ties the purchase to remote config contexts
    screenUid: "scr_42"                // the screen that initiated the purchase
)
let result = try await Qonversion.shared.purchase(product, options: options)
```

`contextKeys` and `screenUid` survive the whole purchase lifecycle — including Ask to Buy approvals that arrive days later and app restarts in between.

Promotional offers (win-back discounts for existing subscribers) are signed by Qonversion — no server code on your side:

```swift
let offer = try await Qonversion.shared.getPromotionalOffer(for: product, discountId: "promo_id")
let options = Qonversion.PurchaseOptions(promoOffer: offer)
let result = try await Qonversion.shared.purchase(product, options: options)
```

**If Qonversion is unreachable at purchase time**, the purchase still succeeds: entitlements are calculated on the device, the report is queued and re-sent on the next launch, and the transaction stays unfinished until the backend confirms it. You never lose a sale to a network hiccup.

### Checking access

```swift
let entitlements = try await Qonversion.shared.checkEntitlements()

if let premium = entitlements["premium"], premium.active {
    // unlock the feature
}
```

| Field | Meaning |
|---|---|
| `active` | Whether the access is currently granted. The only field you need for gating. |
| `source` | Where the purchase came from: `.appStore`, `.playStore`, `.stripe`, `.manual`. |
| `renewState` | `.willRenew`, `.canceled` (active until expiration), `.billingIssue` (grace period — worth a payment-update prompt). |
| `startedDate` / `expirationDate` | Period bounds; `expirationDate == nil` means lifetime access. |
| `productId` | The Qonversion product that granted the access. |

**Offline behavior.** When Qonversion is unreachable (5xx / connection issues), entitlements are calculated locally from StoreKit data, the persisted cache (see `entitlementsCacheLifetime`) and the product → entitlements mapping — access checks keep working through outages. For the very first launch without a network connection, bundle a `qonversion_ios_fallbacks.json` file into the app:

```json
{
    "products": [
        {"id": "pro_monthly", "apple_product_id": "com.app.pro.monthly"}
    ],
    "products_permissions": {
        "pro_monthly": ["premium"]
    }
}
```

### Listening for updates

Both streams follow the style of StoreKit's `Transaction.updates`: every access returns an independent stream, so subscribe from as many places as you need. Start the listeners once, right after initialization:

```swift
Task {
    for await entitlements in Qonversion.shared.entitlementsUpdates {
        // fired after the SDK processes an out-of-band transaction:
        // renewals, Ask to Buy approvals, purchases on other devices,
        // offer code redemptions
        refreshUI(with: entitlements)
    }
}

Task {
    for await intent in Qonversion.shared.promoPurchaseIntents {
        // a purchase started from the App Store product page;
        // call purchase() now, or keep the intent and trigger it
        // when the app is ready (e.g. after onboarding)
        let result = try await intent.purchase()
    }
}
```

Promo purchase intents arriving before your subscription are buffered — subscribing late (after onboarding) is safe.

### Restore and historical data

```swift
let entitlements = try await Qonversion.shared.restore()
```

Restore syncs the user's App Store purchases with Qonversion and returns the resulting entitlements. If the purchases turn out to belong to another Qonversion user, the SDK switches to that user — the same account ends up with the access on every device. If the App Store is unreachable but Qonversion knows the user's entitlements, they are returned instead of an error.

```swift
Qonversion.shared.syncHistoricalData()
```

Call it once after the first launch of the app version that integrates the SDK — it reports the user's past transactions so existing subscribers appear in the analytics with their real history. The SDK guarantees it runs at most once per install.

### Analytics mode

Keep your own StoreKit 2 purchase code and feed the results to Qonversion:

```swift
// your purchase flow
let result = try await storeProduct.purchase()
if case .success(let verificationResult) = result {
    await Qonversion.shared.handlePurchases([verificationResult])
}

// and your transaction updates listener
for await update in StoreKit.Transaction.updates {
    await Qonversion.shared.handlePurchases([update])
}
```

The SDK reports these purchases for analytics and never finishes the transactions — your app owns their lifecycle. Repeated reports of the same transaction are deduplicated, so passing both the purchase result and the updates stream is safe.

### User properties

Properties power segmentation in analytics and are passed to integrations (AppsFlyer, Adjust, Firebase, etc.). They are batched and sent with a small delay:

```swift
Qonversion.shared.setUserProperty("test@example.com", key: .email)
Qonversion.shared.setUserProperty("af_id_123", key: .appsFlyerUserId)
Qonversion.shared.setCustomUserProperty("gold", key: "tier")

let properties = try await Qonversion.shared.userProperties()
```

Defined keys: `.email`, `.name`, `.userId`, `.advertisingId`, `.appsFlyerUserId`, `.adjustAdId`, `.kochavaDeviceId`, `.firebaseAppInstanceId`, `.appMetricaDeviceId`, `.appMetricaUserProfileId`, `.pushWooshUserId`, `.pushWooshHwId`.

### Attribution

```swift
// Apple Search Ads (iOS 14.3+): call on launch, the SDK fetches and
// reports the attribution token by itself
Qonversion.shared.collectAppleSearchAdsAttribution()

// IDFA: call after the user grants the App Tracking Transparency permission
Qonversion.shared.collectAdvertisingId()
```

### Remote config

Remote config delivers JSON payloads controlled from the Dashboard and powers A/B experiments — paywall copy, feature flags, pricing tests:

```swift
let remoteConfig = try await Qonversion.shared.remoteConfig()
let paywallTitle = remoteConfig.payload["paywall_title"] as? String

// scoped by context key, e.g. per screen
let onboardingConfig = try await Qonversion.shared.remoteConfig(contextKey: "onboarding")

// experiment info, when the user is in one
remoteConfig.experiment?.name
remoteConfig.experiment?.group.type   // .control / .treatment
```

Link purchases to the experiment that drove them by passing the same context keys to `PurchaseOptions(contextKeys:)`.

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
