#import "QNStoreKitService.h"
#import "QNUtils.h"

@interface QNStoreKitService() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

// Use SKProduct.productIdentifier as hash for fast access to entities
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKPaymentTransaction *> *processingTransactions;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKProductsRequest *> *productRequests;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKProduct *> *products;
@property (nonatomic, copy) NSString *purchasingCurrently;

@end

@implementation QNStoreKitService

- (instancetype)initWithDelegate:(id <QNStoreKitServiceDelegate>)delegate {
    self = [self init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (void)loadProducts:(NSSet <NSString *> *)products {
  SKProductsRequest *request = [SKProductsRequest.alloc initWithProductIdentifiers:products];
  [request setDelegate:self];
  [request start];
}

- (instancetype)init {
  self = super.init;
  if (self) {
    _processingTransactions = [NSMutableDictionary new];
    _productRequests = [NSMutableDictionary new];
    _products = [NSMutableDictionary new];
    
    _purchasingCurrently = nil;
  }

  [SKPaymentQueue.defaultQueue addTransactionObserver:self];
  return self;
}

- (SKProduct *)purchase:(NSString *)productID {
  SKProduct *skProduct = self->_products[productID];
  
  if (skProduct) {
    @synchronized (self) {
      self->_purchasingCurrently = skProduct.productIdentifier;
    }
    
    SKPayment *payment = [SKPayment paymentWithProduct:skProduct];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    
    return skProduct;
  } else {
    return nil;
  }
}

- (void)restore {
  [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (nullable SKProduct *)productAt:(NSString *)productID {
  return _products[productID];
}

// MARK: - SKPaymentTransactionObserver

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
  if ([self.delegate respondsToSelector:@selector(handleRestoreCompletedTransactionsFinished)]) {
    [self.delegate handleRestoreCompletedTransactionsFinished];
  }
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
  if ([self.delegate respondsToSelector:@selector(handleRestoreCompletedTransactionsFailed:)]) {
    [self.delegate handleRestoreCompletedTransactionsFailed:error];
  }
}

- (void)paymentQueue:(nonnull SKPaymentQueue *)queue
 updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
  for (SKPaymentTransaction *transaction in transactions) {
    [self handleTransaction:transaction];
  }
}

- (void)handleTransaction:(nonnull SKPaymentTransaction *)transaction {
  switch (transaction.transactionState) {
    case SKPaymentTransactionStatePurchasing:
      break;
    case SKPaymentTransactionStatePurchased:
      [self handlePurchasedTransaction:transaction];
      break;
    case SKPaymentTransactionStateFailed:
      [self handleFailedTransaction:transaction];
      break;
    case SKPaymentTransactionStateRestored:
      [self handlePurchasedTransaction:transaction];
      break;
    default:
      break;
  }
}

// MARK: - SKProductsRequestDelegate

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
  if (response.products.count == 0) {
    return;
  }
  
  BOOL autoTracked = NO;
  for (SKProduct *product in response.products) {
    [_products setValue:product forKey:product.productIdentifier];
    QONVERSION_LOG(@"Loaded Product %@ with price %@", product.productIdentifier, product.price);
    
    // Transactions for auto-tracking
    SKPaymentTransaction *transaction = [self.processingTransactions objectForKey:product.productIdentifier];
    
    if (transaction) {
      SKProductsRequest *storedRequest = self.productRequests[product.productIdentifier];
      [self.productRequests removeObjectForKey:product.productIdentifier];
      [self.processingTransactions removeObjectForKey:product.productIdentifier];
      [self handleTransaction:transaction];
      
      // Auto-inited requests
      if (response.products.count == 1 && storedRequest) {
        autoTracked = YES;
      }
    }
  }
  
  if (!autoTracked && [self.delegate respondsToSelector:@selector(handleProducts:)]) {
    [self.delegate handleProducts:response.products];
  }
}

// MARK: - Private

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction {
  NSString *productIdentifier = transaction.payment.productIdentifier;
  SKProduct *skProduct = _products[productIdentifier];
  [self finishTransaction:transaction];
  
  if (skProduct) {
    if ([self.delegate respondsToSelector:@selector(handleFailedTransaction:forProduct:)]) {
        [self.delegate handleFailedTransaction:transaction forProduct:skProduct];
    }
    
    return;
  }
}

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction {
  NSString *productIdentifier = transaction.payment.productIdentifier;
  SKProduct *skProduct = _products[productIdentifier];
  [self finishTransaction:transaction];
  
  if (skProduct) {
    if ([self.delegate respondsToSelector:@selector(handlePurchasedTransaction:forProduct:)]) {
        [self.delegate handlePurchasedTransaction:transaction forProduct:skProduct];
    }
    
    return;
  }

  [self processTransaction:transaction productIdentifier:productIdentifier];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
  if ([request isKindOfClass:SKProductsRequest.class] && [self.delegate respondsToSelector:@selector(handleProductsRequestFailed:)]) {
      [self.delegate handleProductsRequestFailed:error];
  }
}

- (void)processTransaction:(SKPaymentTransaction *)transaction productIdentifier:(NSString *)productIdentifier {
  [self.processingTransactions setObject:transaction forKey:productIdentifier];
  NSSet <NSString *> *productSet = [NSSet setWithObject:productIdentifier];
  SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:productSet];
  [self.productRequests setObject:request forKey:productIdentifier];
                                
  request.delegate = self;
  [request start];
}

- (void)finishTransaction:(SKPaymentTransaction *)transaction {
  if (transaction.transactionState == SKPaymentTransactionStateFailed
      || transaction.transactionState == SKPaymentTransactionStatePurchased
      || transaction.transactionState == SKPaymentTransactionStateRestored) {
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
  }
  
  return;
}

@end
