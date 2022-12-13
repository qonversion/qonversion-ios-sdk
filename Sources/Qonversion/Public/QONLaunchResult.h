#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QONEntitlement, QONProduct, QONOfferings, QONIntroEligibility, QONExperimentInfo, QONUser;

typedef NS_ENUM(NSInteger, QONAttributionProvider) {
  QONAttributionProviderAppsFlyer = 0,
  QONAttributionProviderBranch,
  QONAttributionProviderAdjust,
  QONAttributionProviderAppleSearchAds,
  QONAttributionProviderAppleAdServices
} NS_SWIFT_NAME(Qonversion.AttributionProvider);

/**
 Qonversion Defined User Properties
 We defined some common case properties and provided API for adding them
 @see [Product Center](https://qonversion.io/docs/defined-user-properties)
 */
typedef NS_ENUM(NSInteger, QONProperty) {
  QONPropertyEmail = 0,
  QONPropertyName,
  QONPropertyAppsFlyerUserID,
  QONPropertyAdjustAdID,
  QONPropertyKochavaDeviceID,
  QONPropertyAdvertisingID,
  QONPropertyUserID,
  QONPropertyFirebaseAppInstanceId
} NS_SWIFT_NAME(Qonversion.Property);


NS_SWIFT_NAME(Qonversion.LaunchResult)
@interface QONLaunchResult : NSObject <NSCoding>

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
@property (nonatomic, copy) NSDictionary<NSString *, QONExperimentInfo *> *experiments;
/**
 User entitlements
 */
@property (nonatomic, copy) NSDictionary<NSString *, QONEntitlement *> *entitlements;

/**
 All products
 */
@property (nonatomic, copy) NSDictionary<NSString *, QONProduct *> *products;

/**
 Offerings
 */
@property (nonatomic, strong, nullable) QONOfferings *offerings;

/**
 User products
 */
@property (nonatomic, copy) NSDictionary<NSString *, QONProduct *> *userPoducts;


@end

typedef void (^QONLaunchCompletionHandler)(QONLaunchResult *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.LaunchCompletionHandler);

typedef void (^QONEntitlementsCompletionHandler)(NSDictionary<NSString *, QONEntitlement*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.EntitlementsCompletionHandler);

typedef void (^QONPurchaseCompletionHandler)(NSDictionary<NSString *, QONEntitlement*> *result, NSError  *_Nullable error, BOOL cancelled) NS_SWIFT_NAME(Qonversion.PurchaseCompletionHandler);
typedef void (^QONPromoPurchaseCompletionHandler)(QONPurchaseCompletionHandler) NS_SWIFT_NAME(Qonversion.PromoPurchaseCompletionHandler);
typedef void (^QNRestoreCompletionHandler)(NSDictionary<NSString *, QONEntitlement*> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.RestoreCompletionHandler);

typedef void (^QONProductsCompletionHandler)(NSDictionary<NSString *, QONProduct *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ProductsCompletionHandler);

typedef void (^QONEligibilityCompletionHandler)(NSDictionary<NSString *, QONIntroEligibility *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.EligibilityCompletionHandler);

typedef void (^QONExperimentsCompletionHandler)(NSDictionary<NSString *, QONExperimentInfo *> *result, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ExperimentsCompletionHandler);

typedef void (^QONUserInfoCompletionHandler)(QONUser *_Nullable user, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.UserInfoCompletionHandler);

typedef void (^QONOfferingsCompletionHandler)(QONOfferings *_Nullable offerings, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.OfferingsCompletionHandler);

NS_ASSUME_NONNULL_END
