#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^QNStoreKitServiceReceiptFetchCompletionHandler)(void);
typedef void(^QNStoreKitServiceReceiptFetchWithReceiptCompletionHandler)(NSString *);

@protocol QNStoreKitServiceDelegate;

@interface QNStoreKitService : NSObject

@property (nonatomic, weak, nullable) id <QNStoreKitServiceDelegate> delegate;

- (instancetype)initWithDelegate:(id <QNStoreKitServiceDelegate>)delegate;

- (void)loadProducts:(NSSet <NSString *> *)products;
- (nullable SKProduct *)purchase:(NSString *)productID;
- (void)purchaseProduct:(SKProduct *)product;
- (void)presentCodeRedemptionSheet;
- (void)restore;
- (nullable SKProduct *)productAt:(NSString *)productID;
- (void)finishTransaction:(SKPaymentTransaction *)transaction;
- (NSArray<SKProduct *> *)getLoadedProducts;

- (void)receipt:(QNStoreKitServiceReceiptFetchWithReceiptCompletionHandler)completion;

@end

@protocol QNStoreKitServiceDelegate <NSObject>

@optional
- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction forProduct:(SKProduct *)product;
- (void)handleRestoreCompletedTransactionsFinished;
- (void)handleRestoreCompletedTransactionsFailed:(NSError *)error;
- (void)handleProductsRequestFailed:(NSError *)error;
- (void)handleProducts:(NSArray<SKProduct *> *)products;
- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product;
- (void)handleRestoredTransactions:(NSArray<SKPaymentTransaction *> *)transactions;
- (void)handleExcessTransactions:(NSArray<SKPaymentTransaction *> *)transactions;

@end

NS_ASSUME_NONNULL_END
