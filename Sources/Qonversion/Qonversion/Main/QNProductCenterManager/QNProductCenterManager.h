#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"
#import "QONEntitlementsCacheLifetime.h"
#import "QONLaunchMode.h"

@class QONLaunchResult;
@protocol QONPromoPurchasesDelegate, QONEntitlementsUpdateListener;

NS_ASSUME_NONNULL_BEGIN

@interface QNProductCenterManager : NSObject

@property (nonatomic, assign) QONLaunchMode launchMode;

- (void)identify:(NSString *)userID;
- (void)logout;
- (void)setPurchasesDelegate:(id<QONEntitlementsUpdateListener>)delegate;
- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate;
- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime;

- (void)presentCodeRedemptionSheet;

- (void)launchWithCompletion:(nullable QONLaunchCompletionHandler)completion;
- (void)checkPermissions:(QONEntitlementsCompletionHandler)completion;
- (void)purchaseProduct:(QONProduct *)product completion:(QONPurchaseCompletionHandler)completion;
- (void)purchase:(NSString *)productID completion:(QONPurchaseCompletionHandler)completion;
- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion;

- (void)products:(QONProductsCompletionHandler)completion;
- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion;
- (void)offerings:(QONOfferingsCompletionHandler)completion;
- (void)experiments:(QONExperimentsCompletionHandler)completion;

- (void)userInfo:(QONUserInfoCompletionHandler)completion;

- (void)launch:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion;
- (void)sendPushToken;

@end

NS_ASSUME_NONNULL_END
