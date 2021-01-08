#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QNPermission, QNProduct, QNOfferings;

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
@property (nonatomic, copy, readonly) NSString *uid;

/**
 Original Server response time
 */
@property (nonatomic, assign, readonly) NSUInteger timestamp;

/**
 User permissions
 */
@property (nonatomic, copy) NSDictionary<NSString *, QNPermission *> *permissions;

/**
 All products
 */
@property (nonatomic, copy) NSDictionary<NSString *, QNProduct *> *products;

/**
 Offerings
 */
@property (nonatomic, strong, nullable) QNOfferings *offerings;

/**
 User products
 */
@property (nonatomic, copy) NSDictionary<NSString *, QNProduct *> *userPoducts;


@end

typedef void (^QNLaunchCompletionHandler)(QNLaunchResult *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.LaunchCompletionHandler);

typedef void (^QNPermissionCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.PermissionCompletionHandler);

typedef void (^QNPurchaseCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error, BOOL cancelled) NS_SWIFT_NAME(Qonversion.PurchaseCompletionHandler);
typedef void (^QNPromoPurchaseCompletionHandler)(QNPurchaseCompletionHandler) NS_SWIFT_NAME(Qonversion.PromoPurchaseCompletionHandler);
typedef void (^QNRestoreCompletionHandler)(NSDictionary<NSString *, QNPermission*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.RestoreCompletionHandler);

typedef void (^QNProductsCompletionHandler)(NSDictionary<NSString *, QNProduct *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ProductsCompletionHandler);

typedef void (^QNOfferingsCompletionHandler)(QNOfferings *_Nullable offerings, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.OfferingsCompletionHandler);

NS_ASSUME_NONNULL_END
