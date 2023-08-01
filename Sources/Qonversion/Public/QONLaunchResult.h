#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class QONEntitlement, QONProduct, QONOfferings, QONIntroEligibility, QONUser, QONRemoteConfig, QONUserProperties;

typedef NS_ENUM(NSInteger, QONAttributionProvider) {
  QONAttributionProviderAppsFlyer = 0,
  QONAttributionProviderBranch,
  QONAttributionProviderAdjust,
  QONAttributionProviderAppleSearchAds,
  QONAttributionProviderAppleAdServices
} NS_SWIFT_NAME(Qonversion.AttributionProvider);

/**
 Qonversion Defined User Property keys
 We defined some common case properties and provided API for adding them
 @see [Product Center](https://qonversion.io/docs/defined-user-properties)
 */
typedef NS_ENUM(NSInteger, QONUserPropertyKey) {
  QONUserPropertyKeyEmail = 0,
  QONUserPropertyKeyName,
  QONUserPropertyKeyAppsFlyerUserID,
  QONUserPropertyKeyAdjustAdID,
  QONUserPropertyKeyKochavaDeviceID,
  QONUserPropertyKeyAdvertisingID,
  QONUserPropertyKeyUserID,
  QONUserPropertyKeyFirebaseAppInstanceId,
  QONUserPropertyKeyFacebookAttribution, // Android only
  QONUserPropertyKeyAppSetId, // Android only
  QONUserPropertyKeyCustom,
} NS_SWIFT_NAME(Qonversion.UserPropertyKey);

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

typedef void (^QONRemoteConfigCompletionHandler)(QONRemoteConfig *_Nullable remoteConfig, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.RemoteConfigCompletionHandler);

typedef void (^QONExperimentAttachCompletionHandler)(BOOL success, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.ExperimentAttachCompletionHandler);

typedef void (^QONUserInfoCompletionHandler)(QONUser *_Nullable user, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.UserInfoCompletionHandler);

typedef void (^QONOfferingsCompletionHandler)(QONOfferings *_Nullable offerings, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.OfferingsCompletionHandler);

typedef void (^QONUserPropertiesCompletionHandler)(QONUserProperties *_Nullable userProperties, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.UserPropertiesCompletionHandler);

typedef void (^QONDefaultCompletionHandler)(BOOL success, NSError  *_Nullable error) NS_SWIFT_NAME(Qonversion.DefaulthCompletionHandler);

NS_ASSUME_NONNULL_END
