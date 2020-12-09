#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QNPermission, QNProduct;

typedef NS_ENUM(NSInteger, QNAttributionProvider) {
  QNAttributionProviderAppsFlyer = 0,
  QNAttributionProviderBranch,
  QNAttributionProviderAdjust,
  QNAttributionProviderAppleSearchAds
} NS_SWIFT_NAME(Qonversion.AttributionProvider);

/**
 Qonversion Defined User Properties
 We defined some common case properties and provided API for adding them
 @see [Product Center](https://qonversion.io/docs/defined-user-properties)
 */
typedef NS_ENUM(NSInteger, QNProperty) {
  QNPropertyEmail = 0,
  QNPropertyName,
  QNPropertyAppsFlyerUserID,
  QNPropertyAdjustUserID,
  QNPropertyKochavaDeviceID
} NS_SWIFT_NAME(Qonversion.Property);


NS_SWIFT_NAME(Qonversion.LaunchResult)
@interface QNLaunchResult : NSObject <NSCoding>

/**
 Qonversion User Identifier
 */
@property (nonatomic, readonly) NSString *uid;

/**
 Original Server response time
 */
@property (nonatomic, readonly) NSUInteger timestamp;

/**
 User permissions
 */
@property (nonatomic) NSDictionary<NSString *, QNPermission *> *permissions;

/**
 All products
 */
@property (nonatomic) NSDictionary<NSString *, QNProduct *> *products;

/**
 User products
 */
@property (nonatomic) NSDictionary<NSString *, QNProduct *> *userPoducts;


@end

typedef void (^QNLaunchCompletionHandler)(QNLaunchResult *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.LaunchCompletionHandler);

typedef void (^QNPermissionCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.PermissionCompletionHandler);

typedef void (^QNPurchaseCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error, BOOL cancelled) NS_SWIFT_NAME(Qonversion.PurchaseCompletionHandler);
typedef void (^QNPromoPurchaseCompletionHandler)(QNPurchaseCompletionHandler) NS_SWIFT_NAME(Qonversion.PromoPurchaseCompletionHandler);
typedef void (^QNRestoreCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.RestoreCompletionHandler);

typedef void (^QNProductsCompletionHandler)(NSDictionary<NSString *, QNProduct *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ProductsCompletionHandler);

NS_ASSUME_NONNULL_END
