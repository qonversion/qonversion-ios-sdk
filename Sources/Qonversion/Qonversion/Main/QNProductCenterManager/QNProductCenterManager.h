#import <Foundation/Foundation.h>
#import "QONLaunchResult.h"
#import "QONEntitlementsCacheLifetime.h"
#import "QONLaunchMode.h"
#import "QONRemoteConfigManager.h"

@class QONLaunchResult, QONStoreKit2PurchaseModel, QONFallbackService, QONPromotionalOffer, QONPurchaseOptions, SKProductDiscount;
@protocol QONPromoPurchasesDelegate, QONEntitlementsUpdateListener, QNUserInfoServiceInterface, QNIdentityManagerInterface, QNLocalStorage;

NS_ASSUME_NONNULL_BEGIN

@interface QNProductCenterManager : NSObject

@property (nonatomic, assign) QONLaunchMode launchMode;
@property (nonatomic, strong) QONRemoteConfigManager *remoteConfigManager;

- (instancetype)initWithUserInfoService:(id<QNUserInfoServiceInterface>)userInfoService identityManager:(id<QNIdentityManagerInterface>)identityManager localStorage:(id<QNLocalStorage>)localStorage fallbackService:(QONFallbackService *)fallbackService;

- (BOOL)isUserStable;
- (void)identify:(NSString *)userID completion:(nullable QONUserInfoCompletionHandler)completion;
- (void)logout;
- (void)setPurchasesDelegate:(id<QONEntitlementsUpdateListener>)delegate;
- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate;
- (void)setEntitlementsCacheLifetime:(QONEntitlementsCacheLifetime)cacheLifetime;

- (void)presentCodeRedemptionSheet;

- (void)launchWithCompletion:(nullable QONLaunchCompletionHandler)completion;
- (void)checkEntitlements:(QONEntitlementsCompletionHandler)completion;
- (void)purchase:(QONProduct * _Nonnull)product options:(QONPurchaseOptions * _Nullable)options completion:(nonnull QONPurchaseCompletionHandler)completion;
- (void)purchase:(NSString * _Nonnull)productID purchaseOptions:(QONPurchaseOptions * _Nullable)options completion:(nonnull QONPurchaseCompletionHandler)completion;
- (void)restore:(QNRestoreCompletionHandler)completion;

- (void)products:(QONProductsCompletionHandler)completion;
- (void)checkTrialIntroEligibilityForProductIds:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion;
- (void)offerings:(QONOfferingsCompletionHandler)completion;

- (void)userInfo:(QONUserInfoCompletionHandler)completion;

- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo completion:(QONDefaultCompletionHandler)completion;
- (void)receiptRestore:(QNRestoreCompletionHandler)completion;
- (void)launch:(void (^)(QONLaunchResult * _Nullable result, NSError * _Nullable error))completion;
- (void)getPromotionalOfferForProduct:(QONProduct *)product
                             discount:(SKProductDiscount *)discount 
                           completion:(QONPromotionalOfferCompletionHandler)completion API_AVAILABLE(ios(12.2), macos(10.14.4), watchos(6.2), visionos(1.0));

@end

NS_ASSUME_NONNULL_END
