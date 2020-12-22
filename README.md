<p align="center">
 <a href="https://qonversion.io" target="_blank"><img width="360" height="150" src="https://qonversion.io/img/q_brand.svg"></a>
</p>

<p align="center">
     <a href="https://qonversion.io"><img width="660" src="https://qonversion.io/img/images/product-center.svg">
     </a>
</p>


<p>
Qonversion provides full in-app purchases infrastructure, so you do not need to build your own server for receipt validation.
</p>


<p>
Implement in-app subscriptions, validate user receipts, check subscription status, and provide access to your app features and content using our StoreKit wrapper and Google Play Billing wrapper.
</p>

Check the [documentation](https://docs.qonversion.io) to learn details on implementing and using Qonversion SDKs.

[![Version](https://img.shields.io/cocoapods/v/Qonversion.svg?style=flat)](https://cocoapods.org/pods/Qonversion)
[![Platform](https://img.shields.io/cocoapods/p/Qonversion.svg?style=flat)](https://cocoapods.org/pods/Qonversion)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![MIT License](http://img.shields.io/cocoapods/l/Qonversion.svg?style=flat)](http://qonversion.io)


## Product Center

<p align="center">
     <a href="https://qonversion.io"><img width="400" src="https://qonversion.io/img/images/product-center-scheme.svg">
     </a>
</p>

1. Application calls the purchase method to initialize Qonversion SDK.
2. Qonversion SDK communicates with StoreKit or Google Billing Client to make a purchase.
3. If a purchase is successful, the SDK sends a request to Qonversion API for server-to-server purchase validation. Qonversion server receives accurate information on the in-app purchase status and user entitlements.
4. SDK returns control to the application with a processing state.

## Analytics

Monitor your in-app revenue metrics. Understand your customers and make better decisions with precise subscription revenue data.

<p align="center">
     <a href="https://qonversion.io"><img width="90%" src="https://qonversion.io/img/screenshots/desktop/mobile_subscription_analytics.jpg">
     </a>
</p>

## Integrations

Share your iOS and Android in-app subscription data with your favorite platforms.


<p align="center">
     <a href="https://qonversion.io"><img width="500" src="https://qonversion.io/img/illustrations/pic-integration.svg">
     </a>
</p>


## License

Qonversion SDK is available under the MIT license.
