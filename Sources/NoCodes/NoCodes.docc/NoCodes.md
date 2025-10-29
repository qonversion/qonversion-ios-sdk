# ``NoCodes``

Qonversion No-Codes SDK is a standalone software development kit designed to help you build and customize paywall and onboarding screens without writing code. It allows seamless integration of pre-built subscription UI components and onboarding flows, enabling a faster and more flexible way to design paywalls and user onboarding experiences directly within your app. While it operates independently, the No-Codes SDK relies on the Qonversion SDK as a dependency to handle in-app purchases and subscription management.

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

The **Qonversion No-Code Builder SDK** is the fastest way to design and implement paywalls and onboarding flows in your app. Skip the development time with a **drag-and-drop editor, built-in A/B testing, and real-time analytics**. Whether you're a developer, marketer, or product manager, this SDK makes **optimizing revenue and user experience easier than ever.**

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
