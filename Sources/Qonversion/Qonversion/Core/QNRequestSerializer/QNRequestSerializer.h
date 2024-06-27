#import "QONLaunchResult.h"

@class SKProduct, SKPaymentTransaction, SKProductDiscount, QNProductPurchaseModel, QONProduct, QONStoreKit2PurchaseModel;

NS_ASSUME_NONNULL_BEGIN
@interface QNRequestSerializer : NSObject

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction
                       receipt:(nullable NSString *)receipt;

- (NSDictionary *)introTrialEligibilityDataForProducts:(NSArray<QONProduct *> *)products;
- (NSDictionary *)pushTokenData;

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider;
- (NSDictionary *)purchaseInfo:(QONStoreKit2PurchaseModel *)purchaseInfo
                       receipt:(nullable NSString *)receipt;

- (NSDictionary *)promotionalOfferInfoForProduct:(QONProduct *)product
                                        discount:(SKProductDiscount *)productDiscount
                                      identityId:(NSString *)identityId
                                         receipt:(nullable NSString *)receipt;

@end

NS_ASSUME_NONNULL_END
