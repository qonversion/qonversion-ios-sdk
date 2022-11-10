#import "QONLaunchResult.h"

@class SKProduct, SKPaymentTransaction, QNProductPurchaseModel;

NS_ASSUME_NONNULL_BEGIN
@interface QNRequestSerializer : NSObject

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction
                       receipt:(nullable NSString *)receipt
                 purchaseModel:(nullable QNProductPurchaseModel *)purchaseModel;

- (NSDictionary *)introTrialEligibilityDataForProducts:(NSArray<QONProduct *> *)products;
- (NSDictionary *)pushTokenData;

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QNAttributionProvider)provider;

@end

NS_ASSUME_NONNULL_END
