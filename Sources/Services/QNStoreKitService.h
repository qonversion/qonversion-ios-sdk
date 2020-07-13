#import <StoreKit/StoreKit.h>

@interface QNStoreKitService : NSObject

@end

@protocol QNStoreKitServiceDelegate <NSObject>

@optional
- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;

@end

