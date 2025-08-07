#import "QONLaunchResult.h"

@class SKProduct, SKPaymentTransaction, SKProductDiscount, QNProductPurchaseModel, QONProduct, QONStoreKit2PurchaseModel, QONPurchaseOptions;

NS_ASSUME_NONNULL_BEGIN
@interface QNRequestSerializer : NSObject

- (NSDictionary *)launchData;

- (NSDictionary *)purchaseData:(SKProduct *)product
                   transaction:(SKPaymentTransaction *)transaction
                       receipt:(nullable NSString *)receipt
               purchaseOptions:(nullable QONPurchaseOptions *)purchaseOptions;

- (NSDictionary *)introTrialEligibilityDataForProducts:(NSArray<QONProduct *> *)products;

- (NSDictionary *)attributionDataWithDict:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider;
- (NSDictionary *)purchaseInfo:(QONStoreKit2PurchaseModel *)purchaseInfo
                       receipt:(nullable NSString *)receipt;

- (NSURLRequest *)addTryCountToHeader:(NSNumber *)tryCount request:(NSURLRequest *)request;

- (NSDictionary *)promotionalOfferInfoForProduct:(QONProduct *)product
                                      identityId:(NSString *)identityId
                                         receipt:(nullable NSString *)receipt API_AVAILABLE(ios(11.2), macos(10.13.2), visionos(1.0));

@end

NS_ASSUME_NONNULL_END
