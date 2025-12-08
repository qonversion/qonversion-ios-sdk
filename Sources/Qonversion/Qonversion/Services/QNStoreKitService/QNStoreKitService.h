#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^QNStoreKitServiceReceiptFetchCompletionHandler)(void);
typedef void(^QNStoreKitServiceReceiptFetchWithReceiptCompletionHandler)(NSString *);

@class QONPromotionalOffer, QONPurchaseOptions;
@protocol QNStoreKitServiceDelegate;

@interface QNStoreKitService : NSObject

@property (nonatomic, weak, nullable) id <QNStoreKitServiceDelegate> delegate;

- (instancetype)initWithDelegate:(id <QNStoreKitServiceDelegate>)delegate;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)loadProducts:(NSSet <NSString *> *)products;
- (SKProduct *)purchase:(NSString *)productID options:(QONPurchaseOptions * _Nullable)options identityId:(NSString *)identityId;
- (void)purchaseProduct:(SKProduct *)product;
- (void)presentCodeRedemptionSheet;
- (void)restore;
- (nullable SKProduct *)productAt:(NSString *)productID;
- (void)finishTransaction:(SKPaymentTransaction *)transaction;
- (NSArray<SKProduct *> *)getLoadedProducts;
#pragma clang diagnostic pop

- (void)receipt:(QNStoreKitServiceReceiptFetchWithReceiptCompletionHandler)completion;

@end

@protocol QNStoreKitServiceDelegate <NSObject>

@optional
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
#pragma clang diagnostic pop
- (void)handleRestoreCompletedTransactionsFinished;
- (void)handleRestoreCompletedTransactionsFailed:(NSError *)error;
- (void)handleProductsRequestFailed:(NSError *)error;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)handleProducts:(NSArray<SKProduct *> *)products;
#pragma clang diagnostic pop
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product;
- (void)handleRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions;
- (void)handleExcessTransactions:(NSArray<SKPaymentTransaction *> *)transactions;
#pragma clang diagnostic pop

@end

NS_ASSUME_NONNULL_END
