#import <Foundation/Foundation.h>
#import "QNLaunchResult.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QNAttributionProvider) {
  QNAttributionProviderAppsFlyer = 0,
  QNAttributionProviderBranch,
  QNAttributionProviderAdjust,
  QNAttributionProviderApple
} NS_SWIFT_NAME(Qonversion.AttributionProvider);

typedef void (^QNLaunchCompletionHandler)(QNLaunchResult *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.LaunchCompletionHandler);

typedef void (^QNPermissionCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.PermissionCompletionHandler);

typedef void (^QNPurchaseCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error, BOOL cancelled) NS_SWIFT_NAME(Qonversion.PurchaseCompletionHandler);

typedef void (^QNProductsCompletionHandler)(NSDictionary<NSString *, QNProduct *> *) NS_SWIFT_NAME(Qonversion.ProductsCompletionHandler);

/**
 Qonversion Defined User Properties
 We defined some common case properties and provided API for adding them
 @see [Product Center](https://qonversion.io/docs/defined-user-properties)
 */
typedef NS_ENUM(NSInteger, QNProperty) {
  QNPropertyEmail = 0,
  QNPropertyName,
  QNPropertyKochavaDeviceID
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
 Return Qonversion Products in assotiation with Store Kit Products
 
 @see [Product Center](https://qonversion.io/docs/product-center)
*/
+ (void)products:(QNProductsCompletionHandler)completion;

+ (void)resetUser;

@end

NS_ASSUME_NONNULL_END
