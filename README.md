<h1 align="center">
    Qonversion
</h1>

Qonversion is the data platform to power in-app subscription revenue growth. 

* fast in-app subscriptions implementation
* back-end infrastructure to validate user receipts
* manage cross-platform user access to paid content on your app
* comprehensive subscription analytics
* out-of-the-box integrations with the leading marketing, attribution, and product analytics platforms
* push notifications and in-app messaging to win back lapsed subscribers
* A/B Testing for in-app purchases

<p align="center">
     <a href="https://qonversion.io"><img width="90%" src="https://qcdn3.sfo3.digitaloceanspaces.com/github/qonversion_platform.png">
     </a>
</p>

[![Platform](https://img.shields.io/cocoapods/p/Qonversion.svg?style=flat)](https://documentation.qonversion.io/docs/ios-sdk-setup)
[![Version](https://img.shields.io/cocoapods/v/Qonversion.svg?style=flat)](https://documentation.qonversion.io/docs/ios-sdk-setup#install-via-cocoapods)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://documentation.qonversion.io/docs/ios-sdk-setup#install-via-carthage)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-4BC51D.svg?style=flat)](https://documentation.qonversion.io/docs/ios-sdk-setup#install-via-swift-package-manager)
[![MIT License](http://img.shields.io/cocoapods/l/Qonversion.svg?style=flat)](https://qonversion.io)


## How It Works: Product Center

<p align="center">
     <a href="https://documentation.qonversion.io/docs/integrations-overview"><img width="90%" src="https://user-images.githubusercontent.com/13959241/161107203-8ef3ecee-86be-47a2-ac57-b21d3da19339.png">
     </a>
</p>

1. Application calls the purchase method of Qonversion SDK.
2. Qonversion SDK communicates with StoreKit or Google Billing Client to make a purchase.
3. If a purchase is successful, the SDK sends a request to Qonversion API for server-to-server purchase validation. Qonversion server receives accurate information on the in-app purchase status and user entitlements.
4. SDK returns control to the application with a processing state.

## Analytics

Monitor your in-app revenue metrics. Understand your customers and make better decisions with precise subscription revenue data.

<p align="center">
     <a href="https://documentation.qonversion.io/docs/analytics"><img width="90%" src="https://qonversion.io/img/screenshots/desktop/mobile_subscription_analytics.jpg">
     </a>
</p>

## Integrations

Send subscription data to your favorite platforms Share your mobile and web subscription data using our powerful integrations.

<p align="center">
     <a href="https://documentation.qonversion.io/docs/integrations-overview"><img width="90%", src="https://qcdn3.sfo3.digitaloceanspaces.com/github/integrations.png">
     </a>
</p>

## Personalized push notifications & in-app messaging

Qonversion allows sending automated, personalized push notifications and in-app messages initiated by in-app purchase events. This feature is designed to increase your app's revenue and retention, provide cancellation insights, reduce subscriber churn, and improve your subscribers' user experience.


See more in the [documentation](https://documentation.qonversion.io/docs/automations)
![](https://qonversion.io/img/@2x/automation/in-app-constructor.gif)

## A/B Testing for in-app purchases

Boost conversion rates with paywalls and in-app purchases A/B testing. Find the best pricing and paywall variations. Be flexible to prove hypotheses without app releases.

<p align="center">
     <a href="https://documentation.qonversion.io/docs/subscription-ab-testing"><img width="90%" src="https://user-images.githubusercontent.com/13959241/161716071-b30311b3-b60f-482d-a5d3-c40c1951253b.png">
     </a>
</p>

## Why Qonversion?

* **No headaches with Apple's StoreKit & Google Billing.** Qonversion provides simple methods to handle Apple StoreKit & Google Billing purchase flow.
* **Receipt validation.** Qonversion validates user receipts with Apple and Google to provide 100% accurate purchase information and subscription statuses. It also prevents unauthorized access to the premium features of your app.
* **Track and increase your revenue.** Qonversion provides detailed real-time revenue analytics including cohort analysis, trial conversion rates, country segmentation, and much more.
* **Integrations with the leading mobile platforms.** Qonversion allows sending data to platforms like AppsFlyer, Adjust, Branch, Tenjin, Facebook Ads, Amplitude, Mixpanel, and many others.
* **Change promoted in-app products.** Change promoted in-app products anytime without app releases.
* **Win back lapsed subscribers.** Qonversion allows sending highly targeted push notifications triggered by server-side subscription events. You can send special offers to users who just canceled a free trial or a subscription. Plus you can deliver in-app messages with a beautiful native design that you create in Qonversion.
* **A/B test** and identify winning in-app purchases, subscriptions or paywals.
* **Cross-device and cross-platform access management.** If you provide user authorization in your app, you can easily set Qonversion to provide premium access to authorized users across devices and operating systems.
* **SDK caches the data.** Qonversion SDK caches purchase data including in-app products and permissions, so the user experience is not affected even with the slow or interrupting network connection.
* **Webhooks.** You can easily send all of the data to your server with Qonversion webhooks.
* **Customer support.** You can always reach out to our customer support and get the help required.

Convinced? Let's go!

## Getting Started

1. [Create a project and register your app](https://documentation.qonversion.io/docs/quickstart#1-create-a-project-and-register-your-app)
2. [Configure entitlements](https://documentation.qonversion.io/docs/quickstart#2-configure-products--permissions-entitlements)
3. [Install the SDK](https://documentation.qonversion.io/docs/ios-sdk-setup)
4. [Use all SDK features in a few lines](https://documentation.qonversion.io/docs/using-the-sdks)

## Documentation

Check the [documentation](https://docs.qonversion.io) to learn details on implementing and using Qonversion SDKs.

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
