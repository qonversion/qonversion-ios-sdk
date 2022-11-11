#import <StoreKit/StoreKit.h>

#import "QONLaunchResult.h"
#import "QONProduct.h"
#import "QONEntitlement.h"
#import "QONOfferings.h"
#import "QONOffering.h"
#import "QONIntroEligibility.h"
#import "QONPromoPurchasesDelegate.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONExperimentInfo.h"
#import "QONExperimentGroup.h"
#import "QONUser.h"
#import "QONErrors.h"
#import "QONStoreKitSugare.h"
#import "QONEntitlementsCacheLifetime.h"
#import "QONConfiguration.h"

#if TARGET_OS_IOS
#import "QONAutomationsDelegate.h"
#import "QONAutomations.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface Qonversion : NSObject

/**
 Use `initWithConfig` instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 An entry point to use Qonversion SDK. Call to initialize Qonversion SDK with required and extra configs.
 The function is the best way to set additional configs you need to use Qonversion SDK.
 @param configuration a config that contains key SDK settings.
 @return Initialized instance of the Qonversion SDK.
*/
+ (instancetype)initWithConfig:(QONConfiguration *)configuration;

/**
 Use this variable to get a current initialized instance of the Qonversion SDK.
 Please, use the variable only after initializing the SDK.
 @return Current initialized instance of the Qonversion SDK.
*/
+ (instancetype)sharedInstance NS_SWIFT_NAME(shared());

/**
 Call this function to link a user to his unique ID in your system and share purchase data.
 
 @param userID - unique user ID in your system
 */
- (void)identify:(NSString *)userID;

/**
 Call this function to unlink a user from his unique ID in your system and his purchase data.
 */
- (void)logout;

/**
 Set this listener to handle pending purchases like SCA, Ask to buy, etc
 The delegate will be called when the deferred transaction status updates
 @param listener - listener for handling deferred purchases
 */
- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)listener;

/**
 Entitlements cache is used when there are problems with the Qonversion API or internet connection.
 If so, Qonversion will return the last successfully loaded entitlements. The current method allows you to configure how long that cache may be used.
 The default value is QNEntitlementCacheLifetimeMonth.
 @param cacheLifetime desired entitlements cache lifetime duration
 */
- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime;

/**
 Set this delegate to handle AppStore promo purchases
 @param delegate - delegate for handling AppStore promo purchase flow
 */
- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate;

/**
 Shows up a sheet for users to redeem AppStore offer codes
 */
- (void)presentCodeRedemptionSheet API_AVAILABLE(ios(14.0)) API_UNAVAILABLE(tvos, macos, watchos);

/**
 Set push token to Qonversion to enable Qonversion push notifications
 @param token - token data
 */
- (void)setNotificationsToken:(NSData *)token API_AVAILABLE(ios(9.0));

#if TARGET_OS_IOS
/**
 Returns true when a push notification was received from Qonversion.
 Otherwise returns false, so you need to handle a notification yourself
 @param userInfo - notification user info
 */
- (BOOL)handleNotification:(NSDictionary *)userInfo API_AVAILABLE(ios(9.0));

/**
 Get parsed custom payload, which you added to the notification in the dashboard
 @param userInfo - notification user info
 @return a map with custom payload from the notification or nil if it's not provided.
 */
- (NSDictionary *_Nullable)getNotificationCustomPayload:(NSDictionary *)userInfo;
#endif

/**
 Sets Qonversion reservered user properties, like email or one-signal id
 @param property        Defined enum key that will be transformed to string
 @param value               Property value
 */
- (void)setProperty:(QONProperty)property value:(NSString *)value;

/**
 Sets custom user properties
 @param property        Defined enum key that will be transformed to string
 @param value               Property value
 */
- (void)setUserProperty:(NSString *)property value:(NSString *)value;

/**
 Send your attribution data
 @param data Dictionary received by the provider
 @param provider Attribution provider
 */
- (void)addAttributionData:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider;

/**
 Check user entitlements based on product center details
 @param completion Completion block that include entitlements dictionary and error
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
- (void)checkEntitlements:(QONEntitlementsCompletionHandler)completion;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param product Product create in Qonversion Dash
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
- (void)purchaseProduct:(QONProduct *)product completion:(QONPurchaseCompletionHandler)completion;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param productID Product identifier create in Qonversion Dash, pay attention that you should use qonversion id instead Apple Product ID
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
- (void)purchase:(NSString *)productID completion:(QONPurchaseCompletionHandler)completion;

/**
 Restore user entitlements based on product center details
 @param completion Completion block that include entitlements dictionary and error
 @see [Product Center](https://qonversion.io/docs/product-center)
*/
- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion;

/**
 Return Qonversion Products in assotiation with Store Kit Products
 If you get an empty SKProducts be sure your in-app purchases are correctly setted up in AppStore Connect and .storeKit file is available.

 @see [Installing the iOS SDK](https://qonversion.io/docs/apple)
 @see [Product Center](https://qonversion.io/docs/product-center)
*/
- (void)products:(QONProductsCompletionHandler)completion;

/**
 You can check if a user is eligible for an introductory offer, including a free trial. On the Apple platform, users who have not previously used an introductory offer for any products in the same subscription group are eligible for an introductory offer. Use this method to determine eligibility.
 
 You can show only a regular price for users who are not eligible for an introductory offer.
 @param productIds products identifiers that must be checked
 @param completion Completion block that include trial eligibility check result dictionary and error
 */
- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion;

/**
  Return Qonversion Offerings Object
 
  An offering is a group of products that you can offer to a user on a given paywall based on your business logic.
  For example, you can offer one set of products on a paywall immediately after onboarding and another set of products with discounts later on if a user has not converted.
  Offerings allow changing the products offered remotely without releasing app updates.
 
  @see [Offerings](https://qonversion.io/docs/offerings)
  @see [Product Center](https://qonversion.io/docs/product-center)
 */
- (void)offerings:(QONOfferingsCompletionHandler)completion;

- (void)userInfo:(QONUserInfoCompletionHandler)completion;

/**
 Enable attribution collection from Apple Search Ads. NO by default.
 */
- (void)setAppleSearchAdsAttributionEnabled:(BOOL)enable;

/**
 On iOS 14.5+, after requesting the app tracking permission using ATT, you need to notify Qonversion if tracking is allowed and IDFA is available.
 For Qonversion/NoIdfa SDK advertising ID is always empty.
 */
- (void)setAdvertisingID;

@end

NS_ASSUME_NONNULL_END
