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

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+ / visionOS 1.0+
- Purchases run natively on StoreKit 2
- The public API is async/await-first
- A Qonversion project: sign up at [qonversion.io](https://qonversion.io), create products and entitlements in the Dashboard, and grab the project key from **Settings**

### Core concepts

| Concept | What it is |
|---|---|
| **Product** | A Qonversion product linked to an App Store product. You operate Qonversion product ids in code, so changing the underlying store product doesn't require an app release. |
| **Entitlement** | The access level a purchase unlocks (e.g. `premium`). One entitlement can be unlocked by many products across platforms — an Apple subscription and a Stripe payment can grant the same access. Check entitlements, not receipts. |
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

The first call wins: a repeated `initialize(with:)` is ignored in full, and the SDK keeps running with the configuration of the first one. Switching to another project key requires restarting the process — a mismatched repeated call is logged as an error, naming both projects.

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

The bundled fallback file is looked up in the app bundle first and then in the
app's Documents directory, so it can also be dropped there at runtime.

### Launch modes

Pick the mode by who owns the purchase flow — it defines who finishes StoreKit transactions, and finishing them twice or never are both bugs:

| | `.subscriptionManagement` | `.analytics` |
|---|---|---|
| Who calls StoreKit | The SDK (`purchase`, `restore`) | Your own code |
| Who finishes transactions | The SDK — strictly after Qonversion confirms the purchase | Your app; the SDK never touches them |
| How purchases reach Qonversion | Automatically | You pass them via `handlePurchases` |
| Out-of-band transactions (renewals, Ask to Buy, other devices) | The SDK reports **and finishes** them | The SDK reports them, your app finishes them |
| Deferred purchase signal | `deferredPurchases` fires in both modes — the transaction plus the resulting entitlements | same |
| Entitlements | Calculated by Qonversion, with an on-device fallback | Available the same way |

Use `.subscriptionManagement` for a full integration where Qonversion is the source of truth for access. Use `.analytics` when you keep your existing StoreKit code and want revenue analytics, integrations, and the subscribers CRM on top of it.

### Users and identity

Every install starts as an anonymous Qonversion user (`QON_...`). After your own sign-in, link it:

```swift
let user = try await Qonversion.shared.identify("your_user_id")
```

Two outcomes, both handled for you:

- the id is new → it links to the current anonymous user, purchases made before sign-in stay with the account;
- the id is already linked to another Qonversion user (sign-in on a second device) → the SDK switches to that user and drops every user-scoped cache, so entitlements and remote configs are re-fetched for the right account.

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
    product.storeProduct         // StoreKit.Product?, nil until the store answers
    product.isStoreProductLinked // whether the store product is attached
}
```

### Trial and intro eligibility

Show "Start your free trial" only to users who will actually get one. The eligibility itself is decided on the device by StoreKit 2 (subscription group history); the SDK only needs your product catalog to map a Qonversion id to a store id, and serves that from its cache whenever it has one. A catalog it cannot resolve at all makes the call answer `.unknown` — it never fails:

```swift
let eligibility = try await Qonversion.shared.checkTrialIntroEligibility(["pro_monthly", "pro_annual"])

switch eligibility["pro_monthly"] {
case .eligible:                 break // show the trial CTA
case .ineligible:               break // trial already consumed — show the regular price
case .nonIntroOrTrialProduct:   break // no intro offer configured
case .unknown, .none:           break // the store did not answer, or the id is not in your catalog
}
```

### Making purchases

```swift
let products = try await Qonversion.shared.products()
let result = try await Qonversion.shared.purchase(products[0])

result.transaction                            // the verified store transaction
result.entitlements["premium"]?.active        // access right after the purchase
```

The transaction is finished **only after Qonversion confirms the purchase** — an unreported purchase is never lost. A user cancellation and a pending purchase (Ask to Buy, SCA) surface as typed errors — react precisely instead of showing a generic failure:

```swift
do {
    let result = try await Qonversion.shared.purchase(product)
} catch let error as QonversionError {
    switch error.type {
    case .purchaseCancelled: break     // the user changed their mind — not a failure
    case .purchasePending: break       // completes later via deferredPurchases
    default: showError(error.message)  // error.error carries the underlying failure
    }
}
```

When the failure came from the Qonversion API, `error.apiCode` carries the
backend code verbatim (`relation_not_found`, `purchase_fraud`, …) and
`error.apiType` its class (`internal`, `logical`, `request`, `resource`) — for
handling more specific than `error.type`.

**On visionOS**, name the scene the purchase sheet is confirmed in before
purchasing; StoreKit has no scene-less purchase call there:

```swift
Qonversion.shared.setPurchaseConfirmationScene(windowScene)   // visionOS only
```

Call it after `Qonversion.initialize(with:)` — earlier and the scene is dropped
with a warning in the log. Purchasing without it throws `.purchaseSceneMissing`
rather than crashing.

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

Eligibility is Qonversion's answer, and "not eligible" is a normal one: it arrives as a `QonversionError` of type `.promoOfferNotEligible` and means the paywall shows the full price.

If you map purchases to your own accounts with an `appAccountToken`, pass the same value to both calls — the App Store checks the signed offer against the token the purchase carries:

```swift
let token = UUID()
let offer = try await Qonversion.shared.getPromotionalOffer(for: product, discountId: "promo_id", appAccountToken: token)
let options = Qonversion.PurchaseOptions(promoOffer: offer, appAccountToken: token)
```

**If Qonversion is unreachable at purchase time**, the purchase still succeeds: entitlements are calculated on the device, the report is queued and re-sent on the next launch, and the transaction stays unfinished until the backend confirms it. You never lose a sale to a network hiccup.

### Checking access

```swift
let entitlements = try await Qonversion.shared.checkEntitlements()

if let premium = entitlements["premium"], premium.active {
    // unlock the feature
}
```

Call it as often as you need — on every screen, on every appearance. A backend answer is served straight from the cache for five minutes, concurrent calls share a single request, and the cache is refreshed early if it holds an entitlement that has passed its own expiration.

| Field | Meaning |
|---|---|
| `active` | Whether the access is currently granted. The only field you need for gating. |
| `source` | Where the purchase came from: `.appStore`, `.playStore`, `.stripe`, `.manual`. |
| `renewState` | `.willRenew`, `.canceled` (active until expiration), `.billingIssue` (grace period — worth a payment-update prompt), `.nonRenewable` (a consumable or lifetime purchase — the API sends no subscription for it), `.unknown` (a manual grant, which has no store subscription). |
| `startedDate` / `expirationDate` | Period bounds; `expirationDate == nil` means lifetime access. |
| `productId` | The Qonversion product that granted the access. |

**Offline behavior.** When Qonversion is unreachable (5xx / connection issues), entitlements are calculated locally from StoreKit data, the persisted cache (see `entitlementsCacheLifetime`) and the product → entitlements mapping — access checks keep working through outages. For the very first launch without a network connection, bundle a `qonversion_ios_fallbacks.json` file into the app:

```json
{
    "products": [
        {"id": "pro_monthly", "store_id": "com.app.pro.monthly"}
    ],
    "products_permissions": {
        "pro_monthly": ["premium"]
    },
    "remote_config_list": [
        {
            "payload": {"paywall_title": "Go Pro"},
            "source": {"uid": "src_1", "name": "main", "type": "remote_configuration", "assignment_type": "auto", "context_key": null}
        }
    ]
}
```

The App Store id may also be spelled `apple_product_id` — both keys are read, `store_id` first. Sections and rows are parsed independently, so one malformed row costs you that row and nothing else.

The same file also answers `remoteConfig()` calls when the API is unreachable — bundle the configs your launch screens depend on.

### Listening for updates

The streams follow the style of StoreKit's `Transaction.updates`: every access returns an independent stream. Start the listeners once, right after initialization:

```swift
Task {
    for await purchase in Qonversion.shared.deferredPurchases {
        // fired after the SDK processes an out-of-band transaction:
        // renewals, Ask to Buy and SCA approvals, purchases on other
        // devices, offer code redemptions — in BOTH launch modes
        grantAccess(with: purchase.entitlements, for: purchase.transaction)
    }
}

// Only interested in the access state? Use the entitlements-only projection:
Task {
    for await entitlements in Qonversion.shared.entitlementsUpdates {
        refreshUI(with: entitlements)
    }
}

Task {
    for await intent in Qonversion.shared.promoPurchaseIntents {
        // a purchase started from the App Store product page
        // (delivered on iOS 16.4+ and macOS 14.4+; a known gap on
        // iOS 15.0-16.3. StoreKit has no promoted purchases on
        // watchOS, tvOS or visionOS: there the stream finishes at once);
        // call purchase() now, or keep the intent and trigger it
        // when the app is ready (e.g. after onboarding)
        let result = try await intent.purchase()
    }
}
```

`deferredPurchases` and `promoPurchaseIntents` carry events you act on, so each one is delivered exactly once. An event produced while your loop is running reaches every stream being iterated at that moment; an event produced with nobody listening waits — with no deadline — and goes to the next stream alone, so subscribing late (after onboarding) is safe and a screen that re-appears never grants the same purchase twice. Keep one long-lived loop per event stream, and build the stream where you consume it: a stream you create and drop without iterating counts as having taken what was waiting. A deferred purchase nobody received before the app was terminated comes back on a later launch while its transaction is still unfinished.

`entitlementsUpdates` is the exception: it carries access-state snapshots, so the latest one stays readable by every stream you create afterwards.

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
    let reported = await Qonversion.shared.handlePurchases([verificationResult])
    // false — a report failed or a result was unverified; failed reports
    // are retried automatically by the offline queue
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
Qonversion.shared.setUserProperty(key: .email, value: "test@example.com")
Qonversion.shared.setUserProperty(key: .appsFlyerUserId, value: "af_id_123")
Qonversion.shared.setCustomUserProperty(key: "tier", value: "gold")

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

### IDFA and the Kids Category

**The SDK never links `AdSupport`,** the advertising *identifier* framework. Nothing in the binary references it, so adding Qonversion does not make your app look like it collects the IDFA. Apps for the Kids Category, and any app that declares no tracking, can integrate the SDK as is — there is nothing to disable and nothing to configure.

(The SDK does link `AdServices`, which is a different framework: it is what `collectAppleSearchAdsAttribution()` uses to read the Apple Search Ads attribution token, and it carries no advertising identifier.)

If you *do* want the advertising identifier collected, link `AdSupport` in your own app target:

- **Xcode:** target → *General* → *Frameworks, Libraries, and Embedded Content* → **+** → `AdSupport.framework`.
- **Swift Package Manager:** add `.linkedFramework("AdSupport")` to your target's `linkerSettings`.

The SDK detects the framework at run time and reads the identifier through it, exactly as before. Nothing else changes: `collectAdvertisingId()` keeps the same signature, the identifier still respects App Tracking Transparency, and when the user has not granted the permission the SDK reports no identifier at all.

> Migrating from the Objective-C SDK? The `Qonversion/NoIdfa` subspec is gone and no longer needed — it was the opt-*out*; not linking the framework is now the default, and linking it is the opt-*in*.

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

### No-Codes

No-Codes screens are paywalls and onboarding flows designed in the Qonversion Dashboard and delivered to the app without a release. The feature is iOS-only: the library resolves on the other platforms so a multi-platform package can depend on it unconditionally, but it exposes no entry point there.

They ship as a separate `NoCodes` library in the same package — add it to your app target next to `Qonversion`:

```swift
.product(name: "NoCodes", package: "qonversion-ios-sdk")
```

Initialize it after the main SDK, with the same project key:

```swift
import NoCodes

let noCodesConfiguration = NoCodesConfiguration(projectKey: "YOUR_PROJECT_KEY")
NoCodes.initialize(with: noCodesConfiguration)
```

Screens marked **Preload** in the builder are fetched right away, so showing one is a single call. A screen is addressed by its context key — the same key you assign in the Dashboard:

```swift
NoCodes.shared.showScreen(withContextKey: "main_paywall")
```

The screen presents immediately with a loading skeleton and fills in when the content arrives. To decide before anything is presented — show your own UI when no screen is configured — load it first:

```swift
do {
    let screen = try await NoCodes.shared.loadScreen(withContextKey: "main_paywall")
    // the screen's default variables from the builder, readable before presenting
    let title = screen.defaultVariable(forKey: "headline")?.value.stringValue
    NoCodes.shared.showScreen(withContextKey: "main_paywall")  // renders from the warm cache
} catch {
    presentOwnPaywall()
}
```

Everything that happens inside a screen is reported through delegates you set once:

| Delegate | What it does |
|---|---|
| `NoCodesDelegate` | The flow lifecycle: screen shown, action started / finished / failed, custom actions, flow finished, screen failed to load. Also supplies the view controller to present from. |
| `NoCodesScreenCustomizationDelegate` | How a screen is presented: full screen, push or popover, animated or not, plus a custom loading view. |
| `NoCodesCustomVariablesDelegate` | Values injected into the screen's JavaScript context before it is displayed. |
| `NoCodesPurchaseDelegate` | Optional. Takes over purchases and restores — see below. |

```swift
NoCodes.shared.set(delegate: self)
NoCodes.shared.set(screenCustomizationDelegate: self)
NoCodes.shared.close()   // dismiss the whole No-Codes flow
```

All four delegates are held weakly, like any UIKit delegate — keep your own strong reference to them. Every method has a default implementation, so implement only what you need; watch the signatures, since a misspelled one compiles and silently stops receiving callbacks.

Localization and appearance can be pinned from code, overriding the device defaults:

```swift
NoCodes.shared.setLocale("de-DE")   // nil goes back to the system locale
NoCodes.shared.setTheme(.dark)      // .auto follows the device appearance
```

**Purchases.** By default a purchase button on a screen runs the standard Qonversion purchase flow, and the screen uid travels with the report so the revenue is attributed to the screen. If your app already owns the purchase flow (for example in `.analytics` launch mode), provide a `NoCodesPurchaseDelegate` — it replaces the SDK flow entirely, and the screen reacts to whether your implementation returns or throws:

```swift
func purchase(product: Qonversion.Product) async throws { /* your flow */ }
func restore() async throws { /* your flow */ }
```

**Offline behavior.** Bundle a `nocodes_fallbacks.json` file to keep screens working on a first launch without a network connection. It maps context keys to screens, and the SDK falls back to it when the API is unreachable:

```json
{
    "screens": {
        "main_paywall": {
            "id": "scr_42",
            "context_key": "main_paywall",
            "body": "<!DOCTYPE html><html>…</html>"
        }
    }
}
```

Pass `NoCodesConfiguration(projectKey:fallbackFileName:)` to use a different file name.

### Sample

The `Sample` scheme in `Qonversion.xcodeproj` is a working demo of every flow above — set your project key in `AppDelegate` and run. The **No-Codes** button opens a screen that exercises the No-Codes API.

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
