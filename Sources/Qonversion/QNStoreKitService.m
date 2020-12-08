#import "QNStoreKitService.h"
#import "QNUtils.h"
#import "QNUserInfo.h"

@interface QNStoreKitService() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

// Use SKProduct.productIdentifier as hash for fast access to entities
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKPaymentTransaction *> *processingTransactions;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKProductsRequest *> *productRequests;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKProduct *> *products;
@property (nonatomic, strong, readonly) NSMutableArray<QNStoreKitServiceReceiptFetchCompletionHandler> *receiptRefreshCompletionHandlers;
@property (nonatomic, copy) NSString *purchasingCurrently;

@property (nonatomic, strong) SKProductsRequest *productsRequest;
@property (nonatomic, strong) SKRequest *receiptRefreshRequest;

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
  
  [self setProductsRequest:request];
}

- (instancetype)init {
  self = super.init;
  if (self) {
    _processingTransactions = [NSMutableDictionary new];
    _productRequests = [NSMutableDictionary new];
    _products = [NSMutableDictionary new];
    _receiptRefreshCompletionHandlers = [NSMutableArray new];
    
    _purchasingCurrently = nil;
  }
  
  [SKPaymentQueue.defaultQueue addTransactionObserver:self];
  return self;
}

- (SKProduct *)purchase:(NSString *)productID {
  SKProduct *skProduct = self->_products[productID];
  
  if (skProduct) {
    [self purchaseProduct:skProduct];
    
    return skProduct;
  } else {
    return nil;
  }
}

- (void)purchaseProduct:(SKProduct *)product {
  @synchronized (self) {
    self->_purchasingCurrently = product.productIdentifier;
  }
  
  SKPayment *payment = [SKPayment paymentWithProduct:product];
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
  [[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)restore {
  [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (nullable SKProduct *)productAt:(NSString *)productID {
  return _products[productID];
}

- (void)fetchReceipt:(QNStoreKitServiceReceiptFetchCompletionHandler)completion {
  @synchronized(self) {
    [self.receiptRefreshCompletionHandlers addObject:[completion copy]];
    if (!self.receiptRefreshRequest) {
      [self startReceiptRefreshRequest];
    }
  }
}

- (void)receipt:(QNStoreKitServiceReceiptFetchWithReceiptCompletionHandler)completion {
  NSString *receipt = [self receipt];
  if (receipt.length > 0) {
    QONVERSION_LOG(@"❎ Try to fetch user receipt...");
    [self refreshReceipt:completion];
  } else {
    completion(receipt);
  }
}

- (void)refreshReceipt:(QNStoreKitServiceReceiptFetchWithReceiptCompletionHandler)completion {
  [self fetchReceipt:^{
    NSString *newReceipt = [self receipt];
    if (newReceipt == nil || newReceipt.length == 0) {
      QONVERSION_LOG(@"⚠️ Receipt not found");
    } else {
      QONVERSION_LOG(@"✅ Receipt was fetched");
    }
    completion(newReceipt ?: @"");
  }];
}

- (nullable NSString *)receipt {
  NSURL *receiptURL = QNUserInfo.bundle.appStoreReceiptURL;
  
  if (!receiptURL) {
    return nil;
  }
  
  NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
  
  if (!receiptData) {
    return nil;
  }
  
  return [receiptData base64EncodedStringWithOptions:0];
}

// MARK: - SKPaymentTransactionObserver

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
  if ([self.delegate respondsToSelector:@selector(handleRestoreCompletedTransactionsFinished)]) {
    [self.delegate handleRestoreCompletedTransactionsFinished];
  }
}

#if (TARGET_OS_IOS && !TARGET_OS_MACCATALYST) || TARGET_OS_TV
- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product {
  return [self.delegate paymentQueue:queue shouldAddStorePayment:payment forProduct:product];
}
#endif

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

- (void)startReceiptRefreshRequest {
  @synchronized(self) {
    self.receiptRefreshRequest = [self buildReceiptRefreshRequest];
    self.receiptRefreshRequest.delegate = self;
    [self.receiptRefreshRequest start];
  }
}

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
  
  if (skProduct) {
    if ([self.delegate respondsToSelector:@selector(handlePurchasedTransaction:forProduct:)]) {
      [self.delegate handlePurchasedTransaction:transaction forProduct:skProduct];
    }
    
    return;
  }
  
  [self processTransaction:transaction productIdentifier:productIdentifier];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
  if ([request isKindOfClass:SKProductsRequest.class]
      && [self.delegate respondsToSelector:@selector(handleProductsRequestFailed:)]) {
    [self.delegate handleProductsRequestFailed:error];
    return;
  }
  
  if ([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
    [self finishReceiptFetchRequest:request];
  }
}

- (void)requestDidFinish:(SKRequest *)request {
  if ([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
    [self finishReceiptFetchRequest:request];
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

- (SKReceiptRefreshRequest *)buildReceiptRefreshRequest {
  return [[SKReceiptRefreshRequest alloc] init];
}

- (void)finishReceiptFetchRequest:(SKRequest *)request {
  @synchronized(self) {
    self.receiptRefreshRequest = nil;
    NSArray<QNStoreKitServiceReceiptFetchCompletionHandler> *handlers = [self.receiptRefreshCompletionHandlers copy];
    [self.receiptRefreshCompletionHandlers removeAllObjects];
    
    for (QNStoreKitServiceReceiptFetchCompletionHandler handler in handlers) {
      handler();
    }
  }
}

@end
