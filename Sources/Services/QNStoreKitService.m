#import "QNStoreKitService.h"
#import "QNUtils.h"
#import "QNInMemoryStorage.h"
#import "QNUserDefaultsStorage.h"

@interface QNStoreKitService() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

// Storages
@property (nonatomic) QNInMemoryStorage *inMemoryStorage;
@property (nonatomic) QNUserDefaultsStorage *persistentStorage;

// Through whole service we use product id as
// hash for fast access to entities
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SKPaymentTransaction *> *processingTransactions;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SKProductsRequest *> *productRequests;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SKProduct *> *products;

@property (nonatomic, strong) NSString *purchasingCurrently;

@end

@implementation QNStoreKitService

- (instancetype)initWithDelegate:(id <QNStoreKitServiceDelegate>)delegate {
    self = [self init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (instancetype)init {
  self = super.init;
  if (self) {
    _processingTransactions = [[NSMutableDictionary alloc] init];
    _productRequests = [[NSMutableDictionary alloc] init];
    _products = [[NSMutableDictionary alloc] init];
    
    _purchasingCurrently = NULL;
  }

  [SKPaymentQueue.defaultQueue addTransactionObserver:self];
  return self;
}

- (void)logPurchase:(SKProduct *)product transaction:(SKPaymentTransaction *)transaction {
  /*
   NSDictionary *body = [self->_requestSerializer purchaseData:product transaction:transaction];
  NSURLRequest *request = [self->_requestBuilder makePurchaseRequestWith:body];
  
  NSURLSession *session = [[self session] copy];
  
  [[session dataTaskWithRequest:request
              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
    if (!data || ![data isKindOfClass:NSData.class]) {
      return;
    }
    
    NSError *jsonError = [[NSError alloc] init];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    QONVERSION_LOG(@">>> serviceLogPurchase result %@", dict);
  }] resume];
   */
}

// MARK: - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
  // TODO
  QONVERSION_LOG(@">>> restoreCompletedTransactionsFailedWithError %@", error);
}

- (void)paymentQueue:(nonnull SKPaymentQueue *)queue
 updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
  for (SKPaymentTransaction *transaction in transactions) {
    
    switch (transaction.transactionState) {
      case SKPaymentTransactionStatePurchasing:
        break;
      case SKPaymentTransactionStatePurchased:
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        [self handlePurchasedTransaction:transaction];
        break;
      case SKPaymentTransactionStateFailed:
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        [self handleFailedTransaction:transaction];
        break;
      case SKPaymentTransactionStateRestored:
        // Restore
        break;
      default:
        break;
    }
  }
}

// MARK: - SKProductsRequestDelegate

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
  if (response.products.count == 0) {
    return;
  }
  
  for (SKProduct *product in response.products) {
    [_products setValue:product forKey:product.productIdentifier];
    QONVERSION_LOG(@"Loaded Product %@ with price %@", product.productIdentifier, product.price);
    
    // Transactions for auto-tracking
    SKPaymentTransaction *transaction = [self.processingTransactions objectForKey:product.productIdentifier];
    
    if (transaction) {
      [self.productRequests removeObjectForKey:product.productIdentifier];
      [self.processingTransactions removeObjectForKey:product.productIdentifier];
      [self paymentQueue:[SKPaymentQueue defaultQueue] updatedTransactions:@[transaction]];
    }
  }
}

// MARK: - Private

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction {
  NSString *productIdentifier = transaction.payment.productIdentifier;
  SKProduct *skProduct = _products[productIdentifier];
  if (skProduct) {
    [self.delegate handleFailedTransaction:transaction forProduct:skProduct];
    [self finishTransaction:transaction];
    return;
  }
}

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction {
  NSString *productIdentifier = transaction.payment.productIdentifier;
  SKProduct *skProduct = _products[productIdentifier];
  if (skProduct) {
    [self.delegate handlePurchasedTransaction:transaction forProduct:skProduct];
    [self finishTransaction:transaction];
    return;
  }

  [self.processingTransactions setObject:transaction forKey:productIdentifier];
  NSSet <NSString *> *productSet = [NSSet setWithObject:productIdentifier];
  SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:productSet];
  [self.productRequests setObject:request forKey:productIdentifier];
                                
  request.delegate = self;
  [request start];
}

- (void)finishTransaction:(SKPaymentTransaction *)transaction {
  if (transaction.transactionState == SKPaymentTransactionStateFailed
      || transaction.transactionState == SKPaymentTransactionStatePurchased) {
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
  }
  
  return;
}

@end
