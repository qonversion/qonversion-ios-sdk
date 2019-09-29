![Qonversion](https://qonversion.io/img/brand.png)

Feed your Facebook Ad account with the data on high-value users and see how your Ad account will be enriched with offline purchase events data.

[![Version](https://img.shields.io/cocoapods/v/Qonversion.svg?style=flat)](https://cocoapods.org/pods/Qonversion)
[![Platform](https://img.shields.io/cocoapods/p/Qonversion.svg?style=flat)](https://cocoapods.org/pods/Qonversion)

## Simple Installation in 6 steps:

1. Install Facebook's SDK `FBSDKCoreKit` with their [guide](https://developers.facebook.com/docs/ios/getting-started). 

2. Get Facebook's Access Token [here](https://developers.facebook.com/tools/explorer/) (choose your `Application` in top right corner and then `Get App Token` one line below):

![App Token](https://api.monosnap.com/file/download?id=txzyuGApvCQ6SqzhFWg7vEGhQ4c1bv)

You will see the Token:

![Access Token](https://api.monosnap.com/file/download?id=aLTdcBoD31co8oAj9zuwPgZBn2Ot4V)

3. Provide it in your [qonversion.io](https://qonversion.io) account & request the Qonversion API Key to use it in your App to setup the SDK. We're in a beta right now, so no charges on a launch 🤗

4. Also you need to provide `AppStore App Shared Secret` in your [qonversion.io](https://qonversion.io) account  from [appstoreconnect.apple.com](https://appstoreconnect.apple.com). Go your App/Features and open `App-Specific Shared Secret` on the right and generate App's secret:

![App Shared Secret](https://api.monosnap.com/file/download?id=lIwjBASuafZvDMFKiQJfhneUwyPngG)

This shared secret is needed to validate receipts and make offline events triggered by real purchases.  

5. Run `pod install` with `pod 'Qonversion'` in your pod file (Carthage will be supported later).

6. In your `AppDelegate` in the `application:didFinishLaunchingWithOptions:` method, setup the SDK like so:
```
Qonversion.launch(withKey: "projectKey", autoTrackPurchases: true) { (uid) in
    FBSDKAppEvents.setUserID(uid)
}
```

#### Now you will see all purchases in your Facebook Ad account, even if they happen after trial period or app removal (but only in 28-days window - it's a Facebook rule).

SDK will automatically track any purchase events (subscriptions, trials, basic purchases). But If you want to track purchases manually, you can pass `false` in `autoTrackPurchases` and call `trackPurchase:transaction:` on every purchase event in your application.

## Authors

Developed by Team of [Qonversion](https://qonversion.io), and written by [Bogdan Novikov](https://github.com/Axcic) & [Sam Mejlumyan](https://github.com/smejl)

## License

Qonversion SDK is available under the MIT license.
