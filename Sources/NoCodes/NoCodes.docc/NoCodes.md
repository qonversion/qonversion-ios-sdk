# ``NoCodes``

Qonversion No-Codes SDK is a standalone software development kit designed to help you build and customize paywall and onboarding screens without writing code. It allows seamless integration of pre-built subscription UI components and onboarding flows, enabling a faster and more flexible way to design paywalls and user onboarding experiences directly within your app. While it operates independently, the No-Codes SDK relies on the Qonversion SDK as a dependency to handle in-app purchases and subscription management.

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

The **Qonversion No-Code Builder SDK** is the fastest way to design and implement paywalls and onboarding flows in your app. Skip the development time with a **drag-and-drop editor, built-in A/B testing, and real-time analytics**. Whether you're a developer, marketer, or product manager, this SDK makes **optimizing revenue and user experience easier than ever.**

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
- On-demand loads cache an HTML variant without base64-embedded images, while init-time preloading
  caches a base64-embedded variant. If the two race, which variant ends up cached is nondeterministic
  (this only affects image-embedding, not correctness).

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
