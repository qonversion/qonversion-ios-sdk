#import <StoreKit/StoreKit.h>

@protocol QNStoreKitServiceDelegate;

@interface QNStoreKitService : NSObject

- (instancetype)initWithDelegate:(id <QNStoreKitServiceDelegate>)delegate;

@property (nonatomic, weak) id <QNStoreKitServiceDelegate> delegate;

@end


@protocol QNStoreKitServiceDelegate <NSObject>

@optional
- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;

@end
