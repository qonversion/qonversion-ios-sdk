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

- (void)launchWithCompletion:(nullable QNLaunchCompletionHandler)completion;
- (void)checkPermissions:(QNEntitlementsCompletionHandler)completion;
- (void)purchaseProduct:(QONProduct *)product completion:(QNPurchaseCompletionHandler)completion;
- (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion;
- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion;

- (void)products:(QNProductsCompletionHandler)completion;
- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QNEligibilityCompletionHandler)completion;
- (void)offerings:(QNOfferingsCompletionHandler)completion;
- (void)experiments:(QNExperimentsCompletionHandler)completion;

- (void)userInfo:(QNUserInfoCompletionHandler)completion;

- (void)launch:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion;
- (void)sendPushToken;

@end

NS_ASSUME_NONNULL_END
