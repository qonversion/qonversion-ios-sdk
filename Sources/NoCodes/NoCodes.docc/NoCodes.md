# ``NoCodes``

Qonversion No-Codes SDK is a standalone software development kit designed to help you build and customize paywall and onboarding screens without writing code. It allows seamless integration of pre-built subscription UI components and onboarding flows, enabling a faster and more flexible way to design paywalls and user onboarding experiences directly within your app. While it operates independently, the No-Codes SDK relies on the Qonversion SDK as a dependency to handle in-app purchases and subscription management.

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

The **Qonversion No-Code Builder SDK** is the fastest way to design and implement paywalls and onboarding flows in your app. Skip the development time with a **drag-and-drop editor, built-in A/B testing, and real-time analytics**. Whether you're a developer, marketer, or product manager, this SDK makes **optimizing revenue and user experience easier than ever.**

## Getting Started

The module ships as a separate `NoCodes` library that depends on `Qonversion`. Initialize the main
SDK first, then No-Codes with the same project key:

```swift
import Qonversion
import NoCodes

let configuration = Qonversion.Configuration(apiKey: "YOUR_PROJECT_KEY", launchMode: .subscriptionManagement)
Qonversion.initialize(with: configuration)

let noCodesConfiguration = NoCodesConfiguration(projectKey: "YOUR_PROJECT_KEY")
NoCodes.initialize(with: noCodesConfiguration)
```

Initialization starts preloading the screens marked **Preload** in the builder, so a later
``NoCodes/NoCodes/showScreen(withContextKey:)`` renders from cache.

The whole facade is main-actor isolated: it presents UIKit view controllers and hands out UIKit
objects through its delegates, so call it from the main actor.

```swift
NoCodes.shared.showScreen(withContextKey: "main_paywall")
NoCodes.shared.close()
```

## Delegates

Four delegates cover the integration surface. Set them during initialization via
``NoCodesConfiguration``, or afterwards through the facade. Every callback is delivered on the main
actor.

### NoCodesDelegate

Reports the flow lifecycle and supplies the presentation context.

| Method | When it fires |
|---|---|
| ``NoCodesDelegate/controllerForNavigation()`` | Before presenting. Return the view controller the screen should be presented from; `nil` lets the SDK use the topmost one. |
| ``NoCodesDelegate/noCodesHasShownScreen(id:)`` | A screen has been resolved and is being displayed. |
| ``NoCodesDelegate/noCodesStartsExecuting(action:)`` | The user triggered an action — purchase, restore, deeplink, navigation, close. |
| ``NoCodesDelegate/noCodesFinishedExecuting(action:)`` | The action completed successfully. |
| ``NoCodesDelegate/noCodesFailedToExecute(action:error:)`` | The action failed; `error` carries the reason. |
| ``NoCodesDelegate/noCodesReceivedCustomAction(value:)`` | A custom action configured in the builder was triggered. The SDK executes nothing itself — handle the value in your code. The screen stays open. |
| ``NoCodesDelegate/noCodesFinished()`` | The flow is over and the screens are closed. |
| ``NoCodesDelegate/noCodesFailedToLoadScreen(error:)`` | The screen could not be loaded. Close the flow with ``NoCodes/NoCodes/close()``. |

Every method has a default no-op implementation, so implement only what you need.

### NoCodesScreenCustomizationDelegate

Controls how the first screen of a chain is presented and what is shown while it loads.

```swift
func presentationConfigurationForScreen(contextKey: String) -> NoCodesPresentationConfiguration {
    return NoCodesPresentationConfiguration(animated: true, presentationStyle: .fullScreen)
}

func viewForPopoverPresentation() -> UIView? { anchorView }   // iPad popovers only

func noCodesCustomLoadingView() -> NoCodesLoadingView? { MyLoadingView() }
```

``NoCodesPresentationStyle`` offers `.fullScreen` (a modal navigation stack), `.push` (onto the
presenting navigation controller) and `.popover` (iPad, anchored to the view returned by
``NoCodesScreenCustomizationDelegate/viewForPopoverPresentation()``).
``NoCodesPresentationConfiguration`` also carries `statusBarHidden`.

Returning a ``NoCodesLoadingView`` replaces the built-in skeleton; the SDK calls `startAnimating()`
when the screen appears and `stopAnimating()` when the content is ready. Conforming types must be
`UIView` subclasses.

### NoCodesCustomVariablesDelegate

Called each time a screen is about to be displayed, with the context key of that screen. The returned
values are injected into the screen's JavaScript context and can be referenced from the builder.

```swift
func customVariables(for contextKey: String) -> [String: String] {
    return ["userName": currentUser.name]
}
```

The delegate is held weakly — keep your own strong reference to it.

### NoCodesPurchaseDelegate

Optional. When provided — through ``NoCodesConfiguration/purchaseDelegate`` or
``NoCodes/NoCodes/set(purchaseDelegate:)`` — it replaces the default Qonversion purchase flow
entirely: the screen calls your implementation and reacts to whether it returns or throws.

```swift
func purchase(product: Qonversion.Product) async throws { /* your purchase flow */ }
func restore() async throws { /* your restore flow */ }
```

Without the delegate the SDK performs the purchase itself and attaches the screen uid to the report,
so the revenue is attributed to the No-Codes screen in the analytics.

## Theming and Localization

Both can be set during initialization and changed at any point afterwards; the value applies to the
screens shown from then on.

```swift
let configuration = NoCodesConfiguration(projectKey: "your_key", locale: "de-DE", theme: .dark)

NoCodes.shared.setLocale("fr")     // nil goes back to the system locale
NoCodes.shared.setTheme(.auto)     // .auto follows the device appearance
```

``NoCodesTheme/auto`` follows the presenting environment's interface style and keeps following it:
when the user switches appearance while a screen is open, the screen is notified and re-renders. The
locale should be a standard identifier — `"en"`, `"en-US"`, `"de"`, `"de-DE"`.

The screens also receive a context payload built by the SDK: the device block (platform, OS version,
language, locale, country, app version, resolved theme), the user block (first launch, days since
install, active entitlements, user properties) and, for screens that use intro conditions, a products
block with intro eligibility per product. It powers the conditional logic configured in the builder —
no integration code is required.

## Screen Events

The SDK tracks screen analytics on its own: `screen_shown` when a screen appears, `screen_closed`
when it is permanently dismissed, plus the CTA and page-view events the screen itself emits. Events
are buffered and sent in batches of ten, and flushed when the flow finishes, so a short-lived screen
still reports. Failed batches are kept for the next attempt, with the oldest events dropped once the
retry buffer holds a hundred of them. There is no API to call — the events show up in the No-Codes
analytics in the Dashboard.

## Loading Screens Before Presentation

By default, ``NoCodes/NoCodes/showScreen(withContextKey:)`` presents a full-screen skeleton
immediately and loads the content afterwards, so your app only learns the outcome through delegate
callbacks after the screen is already on screen.

Screens with the **Preload** option enabled in the No-Codes builder are fetched automatically at
SDK initialization, so `showScreen` renders them from cache on its own. `loadScreen` is an optional,
additional entry point — not a prerequisite for loading and not the primary source.

Use ``NoCodes/NoCodes/loadScreen(withContextKey:)`` when you want to decide up front — an "ask-first
gate". It awaits the screen's availability and data (from cache or network) *before* anything is
presented, so you can present the screen or show your own fallback UI without the SDK skeleton ever
appearing. A successful load warms the shared cache, so the following `showScreen` renders from cache
with a minimal skeleton.

```swift
do {
    _ = try await NoCodes.shared.loadScreen(withContextKey: key)  // warms cache
    NoCodes.shared.showScreen(withContextKey: key)                // renders from cache
} catch {
    presentOwnFallbackUI()                                        // SDK skeleton never shown
}
```

The thrown ``NoCodesError`` lets you branch on the failure: a `.screenNotFound` type means the screen
is genuinely absent for that context key (show your fallback), while `.screenLoadingFailed` indicates a
transient network or load failure (you may retry). If the SDK is not initialized, the call throws a
`.sdkInitializationError`.

Two known, benign limitations:
- Unlike `showScreen`, `loadScreen` skips `forceSendProperties`, so the targeting basis may differ
  slightly from a direct `showScreen` call.
- Image embedding is preload-only (same as `showScreen`): on-demand fetches cache an un-embedded HTML
  variant, init-time preload embeds base64; if the two race, the cached variant is nondeterministic —
  affects image-embedding only, not correctness or availability.

## Configuration Management

The NoCodes SDK provides flexible configuration options that can be set during initialization or updated later:

### Proxy URL Configuration

If you need to route API requests through a proxy server, you can configure a custom proxy URL:

```swift
// Set proxy URL during initialization
let configuration = NoCodesConfiguration(
    projectKey: "your_project_key",
    proxyURL: "https://your-proxy-server.com"
)
NoCodes.initialize(with: configuration)

// Or set proxy URL using configuration object
var config = NoCodesConfiguration(projectKey: "your_key")
config.proxyURL = "https://your-proxy-server.com"
NoCodes.initialize(with: config)
```

The proxy URL will be automatically normalized by adding the `https://` prefix if not present and ensuring it ends with a trailing slash.

### Dynamic Configuration Updates

You can update configuration parameters using the configuration object:

```swift
var config = NoCodesConfiguration(projectKey: "your_key")
config.delegate = yourDelegate
config.screenCustomizationDelegate = yourCustomizationDelegate
config.fallbackFileName = "custom_fallbacks.json"
config.proxyURL = "https://your-proxy.com"

NoCodes.initialize(with: config)
```

### Fallback File

The bundled fallback file keeps the screens working when the API is unreachable — a first launch
without a network connection, an outage, a blocked domain. Add a `nocodes_fallbacks.json` file to the
app bundle:

```json
{
    "screens": {
        "main_paywall": {
            "id": "scr_42",
            "context_key": "main_paywall",
            "body": "<!DOCTYPE html><html>…</html>",
            "variables": [
                {"kind": "custom", "key": "headline", "type": "string", "value": "Go Pro"},
                {"kind": "selected_product", "key": "default_selected_product", "type": "string", "value": "pro_annual"}
            ]
        }
    }
}
```

- the keys of `screens` are context keys — the same ones passed to
  ``NoCodes/NoCodes/showScreen(withContextKey:)``;
- `id`, `context_key` and `body` (the screen HTML) are required, `variables` is optional and follows
  the shape of ``NoCodesScreen/defaultVariables``; entries without a `kind` are read as custom
  variables;
- the file is read once and cached for the process lifetime;
- the fallback is consulted only for network and server failures. A screen that genuinely does not
  exist for the given context key surfaces as `.screenNotFound` instead, so your app can tell the two
  apart;
- shipping the file also shortens the network timeout, so a failing request reaches the fallback
  faster.

Use ``NoCodesConfiguration/fallbackFileName`` to bundle the file under a different name.

### Configuration Properties

The `NoCodesConfiguration` struct provides mutable properties for all optional parameters:

```swift
var config = NoCodesConfiguration(projectKey: "your_key")

// Set delegate
config.delegate = yourDelegate

// Set screen customization delegate  
config.screenCustomizationDelegate = yourCustomizationDelegate

// Set custom fallback file name
config.fallbackFileName = "custom_fallbacks.json"

// Set proxy URL
config.proxyURL = "https://your-proxy.com"

NoCodes.initialize(with: config)
```
