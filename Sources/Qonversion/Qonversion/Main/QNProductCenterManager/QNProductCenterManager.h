#import <Foundation/Foundation.h>
#import "QNLaunchResult.h"
#import "QNPermissionsCacheLifetime.h"

@class QNLaunchResult;
@protocol QNPromoPurchasesDelegate, QNPurchasesDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface QNProductCenterManager : NSObject

@property (nonatomic, assign) BOOL disableFinishTransactions;

- (void)identify:(NSString *)userID;
- (void)logout;
- (void)setPurchasesDelegate:(id<QNPurchasesDelegate>)delegate;
- (void)setPromoPurchasesDelegate:(id<QNPromoPurchasesDelegate>)delegate;
- (void)setEntitlementsCacheLifetime:(QNPermissionsCacheLifetime)cacheLifetime;

- (void)presentCodeRedemptionSheet;

- (void)launchWithCompletion:(nullable QNLaunchCompletionHandler)completion;
- (void)checkPermissions:(QNPermissionCompletionHandler)completion;
- (void)purchaseProduct:(QNProduct *)product completion:(QNPurchaseCompletionHandler)completion;
- (void)purchase:(NSString *)productID completion:(QNPurchaseCompletionHandler)completion;
- (void)restoreWithCompletion:(QNRestoreCompletionHandler)completion;

- (void)products:(QNProductsCompletionHandler)completion;
- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QNEligibilityCompletionHandler)completion;
- (void)offerings:(QNOfferingsCompletionHandler)completion;
- (void)experiments:(QNExperimentsCompletionHandler)completion;

- (void)userInfo:(QNUserInfoCompletionHandler)completion;

- (void)launch:(void (^)(QNLaunchResult * _Nullable result, NSError * _Nullable error))completion;
- (void)sendPushToken;

@end

NS_ASSUME_NONNULL_END
