<p align="center">
     <a href="https://qonversion.io"><img width="260" src="https://qonversion.io/img/brand.svg"></a>
</p>

<p align="center">
     <a href="https://qonversion.io"><img width="660" src="https://qonversion.io/img/illustrations/charts.svg"></a></p>

Get access to the powerful yet simple subscription analytics:
* Conversion from install to paying user, MRR, LTV, churn and other metrics.
* Feed the advertising and analytics tools you are already using with the data on high-value users to improve your ads targeting and marketing ROAS.

[![Version](https://img.shields.io/cocoapods/v/Qonversion.svg?style=flat)](https://cocoapods.org/pods/Qonversion)
[![Platform](https://img.shields.io/cocoapods/p/Qonversion.svg?style=flat)](https://cocoapods.org/pods/Qonversion)

## Simple Installation:

### CocoaPods

1. Add `pod 'Qonversion'` in your pod file.

2. Run `pod install`

3. In your `AppDelegate` in the `application:didFinishLaunchingWithOptions:` method, setup the SDK like so:

### Swift

```swift
import Qonversion

Qonversion.launch(withKey: "projectKey") { uid in 
   // This is needed for Facebook Ads integration:
   // AppEvents.userID = uid
   
   // This is needed for Amplitude integration:
   // Amplitude.instance()?.setUserId(uid)
}
```

### Objective-C

```objective-c
#import "Qonversion.h"

[Qonversion launchWithKey:@"projectKey" completion:^(NSString * _Nonnull uid) {
   // This is needed for Facebook Ads integration:
   // [FBSDKAppEvents setUserID:uid];
   
   // This is needed for Amplitude integration:
   // [[Amplitude] instance] setUserId:uid];
}]; 
```

#### Now you will see all purchases in your Facebook Ad account, even if they happen after trial period or app removal (but only in 28-days window - it's a Facebook rule).

SDK will automatically track any purchase events (subscriptions, trials, basic purchases). But If you want to track purchases manually, you can pass `false` in `autoTrackPurchases` and call `trackPurchase:transaction:` on every purchase event in your application.

## Authors

Developed by Team of [Qonversion](https://qonversion.io), and written by [Bogdan Novikov](https://github.com/Axcic) & [Sam Mejlumyan](https://github.com/smejl)

## License

Qonversion SDK is available under the MIT license.
