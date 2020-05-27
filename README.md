<p align="center">
 <a href="https://qonversion.io" target="_blank"><img width="460" height="150" src="https://qonversion.io/img/q_brand.svg"></a>
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

If you want to use your user-id instead of Qonversion user-id:

```swift
import Qonversion

Qonversion.launch(withKey: "projectKey", userID: "yourSideUserID")
```


## User Validation


Most app users have only one subscription. For that reason, you can get the first item from `activeProducts` and check its status. 

### Swift

```swift
Qonversion.checkUser({ result in

  guard let activeProduct = result.activeProducts.first else {
    // Flow for users without any active subscription
    return
  }
  
  if activeProduct.state == .trial, activeProduct.status == .active {
    // Flow for users with active subscription
  }
}) { _ in }
```

### Objective-C

```Objective-C
[Qonversion checkUser:^(QonversionCheckResult * _Nonnull result) {
    RenewalProductDetails *activeObject = result.activeProducts.firstObject;
    
    if (activeObject) {
        
    } else {
        // Flow for users without any active subscriptions
    }
    
} failure:^(NSError *error) {
    
}];
```
 For more details, see [docs](https://docs.qonversion.io/getting-started/quick-start-with-ios/user-validation#check-user-subscription).


## License

Qonversion SDK is available under the MIT license.
