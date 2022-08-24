#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QNPermission, QNProduct, QNOfferings, QNIntroEligibility, QNExperimentInfo, QNUser;

typedef NS_ENUM(NSInteger, QNAttributionProvider) {
  QNAttributionProviderAppsFlyer = 0,
  QNAttributionProviderBranch,
  QNAttributionProviderAdjust,
  QNAttributionProviderAppleSearchAds,
  QNAttributionProviderAppleAdServices
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
  QNPropertyKochavaDeviceID,
  QNPropertyAdvertisingID,
  QNPropertyUserID,
  QNPropertyFirebaseAppInstanceId
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
 User A/B-test experiments
 */
@property (nonatomic, copy) NSDictionary<NSString *, QNExperimentInfo *> *experiments;
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

typedef void (^QNEligibilityCompletionHandler)(NSDictionary<NSString *, QNIntroEligibility *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.EligibilityCompletionHandler);

typedef void (^QNExperimentsCompletionHandler)(NSDictionary<NSString *, QNExperimentInfo *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ExperimentsCompletionHandler);

typedef void (^QNUserInfoCompletionHandler)(QNUser *_Nullable user, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.UserInfoCompletionHandler);

typedef void (^QNOfferingsCompletionHandler)(QNOfferings *_Nullable offerings, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.OfferingsCompletionHandler);

NS_ASSUME_NONNULL_END
