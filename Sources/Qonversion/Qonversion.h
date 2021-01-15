#import <StoreKit/StoreKit.h>

#import "QNLaunchResult.h"
#import "QNProduct.h"
#import "QNPermission.h"

@protocol QNPromoPurchasesDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface Qonversion : NSObject

/**
 Launches Qonversion SDK with the given project key, you can get one in your account on dash.qonversion.io
 @param key - project key to setup the SDK
 */
+ (void)launchWithKey:(nonnull NSString *)key;

/**
 @param key - project key to setup the SDK.
 @param completion - will return `uid` for Ads integrations.
 */
+ (void)launchWithKey:(nonnull NSString *)key completion:(QNLaunchCompletionHandler)completion;

+ (void)setPromoPurchasesDelegate:(id<QNPromoPurchasesDelegate>)delegate;

/**
 Sets debug environment for user.
 If debug mode set, user purchases will not be sent to third-party integrations.
 @see [Setting Debug Mode](https://qonversion.io/docs/debug-mode)
 */
+ (void)setDebugMode;

/**
 Sets Qonversion reservered user properties, like email or one-signal id
 @param property        Defined enum key that will be transformed to string
 @param value               Property value
 */
+ (void)setProperty:(QNProperty)property value:(NSString *)value;

/**
 Sets custom user properties
 @param property        Defined enum key that will be transformed to string
 @param value               Property value
 */
+ (void)setUserProperty:(NSString *)property value:(NSString *)value;

/**
 Associate a user with their unique ID in your system
 @param userID            Your database user ID
 */
+ (void)setUserID:(NSString *)userID;

/**
 Send your attribution data
 @param data Dictionary received by the provider
 @param provider Attribution provider
 */
+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider;

/**
 Check user permissions based on product center details
 @param completion Complition block that include permissions dictionary and error
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)checkPermissions:(QNPermissionCompletionHandler)completion;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param productID Product identifier create in Qonversion Dash, pay attention that you should use qonversion id instead Apple Product ID
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion;

/**
 Restore user permissions based on product center details
 @param completion Completion block that include permissions dictionary and error
 @see [Product Center](https://qonversion.io/docs/product-center)
*/
+ (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion;

/**
 Return Qonversion Products in assotiation with Store Kit Products
 If you get an empty SKProducts be sure your in-app purchases are correctly setted up in AppStore Connect and .storeKit file is available.

 @see [Installing the iOS SDK](https://qonversion.io/docs/apple)
 @see [Product Center](https://qonversion.io/docs/product-center)
*/
+ (void)products:(QNProductsCompletionHandler)completion;

+ (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QNEligibilityCompletionHandler)completion;

/**
  Return Qonversion Offerings Object
 
  An offering is a group of products that you can offer to a user on a given paywall based on your business logic.
  For example, you can offer one set of products on a paywall immediately after onboarding and another set of products with discounts later on if a user has not converted.
  Offerings allow changing the products offered remotely without releasing app updates.
 
  @see [Offerings](https://qonversion.io/docs/offerings)
  @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)offerings:(QNOfferingsCompletionHandler)completion;

+ (void)experiments:(QNExperimentsCompletionHandler)completion;

+ (void)resetUser;

/**
 Enable attribution collection from Apple Search Ads. NO by default.
 */
+ (void)setAppleSearchAdsAttributionEnabled:(BOOL)enable;

@end

NS_ASSUME_NONNULL_END
