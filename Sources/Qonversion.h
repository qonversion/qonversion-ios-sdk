#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import "QonversionProduct.h"
#import "QonversionCheckResult.h"
#import "QonversionPermission.h"
#import "QonversionProperties.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^QonversionPermissionCompletionBlock)(NSDictionary<NSString *, QonversionPermission*> *result, NSError  *_Nullable error);
NS_SWIFT_NAME(Qonversion.PermissionCompletionBlock);

typedef void (^QonversionPurchaseCompletionBlock)(NSDictionary<NSString *, QonversionPermission*> *result, NSError  *_Nullable error, BOOL cancelled);
NS_SWIFT_NAME(Qonversion.PurchaseCompletionBlock);

typedef NS_ENUM(NSInteger, QAttributionProvider) {
  QAttributionProviderAppsFlyer = 0,
  QAttributionProviderBranch,
  QAttributionProviderAdjust
};

@interface Qonversion : NSObject

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
+ (void)setProperty:(QProperty)property value:(NSString *)value;

/**
 Sets custom user properties
 @param property        Defined enum key that will be transformed to string
 @param value               Property value
 */
+ (void)setUserProperty:(NSString *)property value:(NSString *)value;

/**
 Launches Qonversion SDK with the given project key, you can get one in your account on qonversion.io.
 @param key - project key to setup the SDK.
 @param completion - will return `uid` for Ads integrations.
 */
+ (void)launchWithKey:(nonnull NSString *)key completion:(nullable void (^)(NSString *uid))completion;

/**
 @param key - project key to setup the SDK.
 @param uid - Client side user-id (instead of Qonversion user-id) will be used for matching data in the third party data.
 */

+ (void)launchWithKey:(nonnull NSString *)key userID:(nonnull NSString *)uid;

/**
 @param key - project key to setup the SDK.
 */
+ (void)launchWithKey:(nonnull NSString *)key;

/**
 Send your attribution data
 @param data Dictionary received by the provider
 @param provider Attribution provider
 */
+ (void)addAttributionData:(NSDictionary *)data
              fromProvider:(QAttributionProvider)provider;

+ (void)checkUser:(void(^)(QonversionCheckResult *result))result
          failure:(QonversionCheckFailer)failure;

/**
 Check user permissions based on product center details
 @param result Complition block that include permissions dictionary and error
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)checkPermissions:(QonversionPermissionCompletionBlock)result;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param productID Product identifier create in Qonversion Dash, pay attention that you should use qonversion id instead Apple Product ID
 @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (void)purchase:(NSString *)productID
          result:(QonversionPurchaseCompletionBlock)result;

/**
  Return Qonverion Product Assotiated with Store Kit Product
  @param productID Product identifier create in Qonversion Dash
  @see [Product Center](https://qonversion.io/docs/product-center)
 */
+ (QonversionProduct *)productWith:(NSString *)productID;

@end

NS_ASSUME_NONNULL_END
