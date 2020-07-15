#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QNProduct, QNPermission, QNLaunchResult;

typedef NS_ENUM(NSInteger, QNAttributionProvider) {
  QNAttributionProviderAppsFlyer = 0,
  QNAttributionProviderBranch,
  QNAttributionProviderAdjust,
  QNAttributionProviderApple
} NS_SWIFT_NAME(Qonversion.AttributionProvider);

typedef void (^QNLaunchCompletionHandler)(QNLaunchResult *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.LaunchCompletionHandler);

typedef void (^QNPermissionCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.PermissionCompletionHandler);

typedef void (^QNPurchaseCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error, BOOL cancelled) NS_SWIFT_NAME(Qonversion.PurchaseCompletionHandler);

typedef void (^QNProductsCompletionHandler)(NSArray<QNProduct *> *) NS_SWIFT_NAME(Qonversion.ProductsCompletionHandler);

typedef NS_ENUM(NSInteger, QNProperty) {
  QNPropertyEmail = 0,
  QNPropertyName,
  QNPropertyPremium
} NS_SWIFT_NAME(Qonversion.Property);

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

/**
 Sets the environment for receipt.
 @param debugMode        true If your app run under debug mode, default: false
 @see [Setting Debug Mode](https://qonversion.io/docs/debug-mode)
 */
+ (void)setDebugMode:(BOOL)debugMode;

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
 Send your attribution data
 @param data Dictionary received by the provider
 @param provider Attribution provider
 */
+ (void)addAttributionData:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider;

/**
 Check user permissions based on product center details
 @param result Complition block that include permissions dictionary and error
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)checkPermissions:(QNPermissionCompletionHandler)result;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param productID Product identifier create in Qonversion Dash, pay attention that you should use qonversion id instead Apple Product ID
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)purchase:(NSString *)productID result:(QNPurchaseCompletionHandler)result;

/**
  Return Qonversion Product Assotiated with Store Kit Product
  @param productID Product identifier create in Qonversion Dash
  @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (QNProduct *)productAt:(NSString *)productID;

- (void)productsWithIDs:(NSArray<NSString *> *)productIDs
             completion:(QNProductsCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
