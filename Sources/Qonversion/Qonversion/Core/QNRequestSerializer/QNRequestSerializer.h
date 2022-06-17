#import "QNLaunchResult.h"

@class SKProduct, SKPaymentTransaction, QNProductPurchaseModel, QNPurchaseInfo;

NS_ASSUME_NONNULL_BEGIN
@interface QNRequestSerializer : NSObject

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction
                       receipt:(nullable NSString *)receipt
                 purchaseModel:(nullable QNProductPurchaseModel *)purchaseModel;

- (NSDictionary *)introTrialEligibilityDataForProducts:(NSArray<QNProduct *> *)products;
- (NSDictionary *)pushTokenData;

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider;
- (NSDictionary *)purchaseInfo:(QNPurchaseInfo *)purchaseInfo receipt:(nullable NSString *)receipt;

@end

NS_ASSUME_NONNULL_END
