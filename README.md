![Qonversion](https://qonversion.io/assets/img/brand.png)

Feed your Facebook Ad account with the data on high-value users and out-of-the-box integration.

## Compatibility
Fully Compatible With iOS 9.0+

## Installation

To install it, add the following line to your Podfile:

```ruby
pod 'Qonversion'
```

Then, in your `AppDelegate` in the `application:didFinishLaunchingWithOptions:` method, setup the SDK:

`Qonversion.launch(withKey: "projectKey", autoTrackPurchases: true, completion: { (uid) in
            //
        })`

1. Need to pass your project key from [qonversion.io](https://qonversion.io) on a launch.

2. In `Qonversion.launch(withKey:autoTrackPurchases:completion:` completion block you will receive unique user id (uid). This uid is for the Facebook SDK. Use it like so: `FBSDKAppEvents.setUserID(uid)` or `FBSDKAppEvents.setUserID = uid` (depends on FBSDK version).


Library automatically tracks any purchase types (subscriptions, trials, basic purchases) if you set `autoTrackPurchases` to `true`. If you want to control the process of purchase tracking manually, just pass `false` in `autoTrackPurchases` and call `trackPurchase:transaction:` on every purchase event in your application.

## Authors

[Bogdan Novikov](https://github.com/Axcic) & [Sam Mejlumyan](https://github.com/smejl)

## License

Qonversion SDK is available under the MIT license. See the LICENSE file for more info.
