#import "QNStoreKitService.h"
#import "QNUtils.h"
#import "QNUserInfo.h"

@interface QNStoreKitService() <SKPaymentTransactionObserver, SKProductsRequestDelegate>

// Use SKProduct.productIdentifier as hash for fast access to entities
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *processingTransactions;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKProductsRequest *> *productRequests;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SKProduct *> *products;
@property (nonatomic, strong, readonly) NSMutableArray<QNStoreKitServiceReceiptFetchCompletionHandler> *receiptRefreshCompletionHandlers;
@property (nonatomic, copy) NSString *purchasingCurrently;
@property (nonatomic, assign) BOOL isProductsLoaded;

@property (nonatomic, strong) SKProductsRequest *productsRequest;
@property (nonatomic, strong) SKReceiptRefreshRequest *receiptRefreshRequest;

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
    _isProductsLoaded = NO;
  }
  
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
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
  [[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)presentCodeRedemptionSheet {
#if TARGET_OS_IOS
  if (@available(iOS 14.0, *)) {
    [[SKPaymentQueue defaultQueue] presentCodeRedemptionSheet];
  }
#endif
}

- (void)restore {
  [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (nullable SKProduct *)productAt:(NSString *)productID {
  return _products[productID];
}

- (NSArray<SKProduct *> *)getLoadedProducts {
  return self.isProductsLoaded ? self.products.allValues : @[];
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
    completion(receipt);
  } else {
    QONVERSION_LOG(@"❎ Try to fetch user receipt...");
    [self refreshReceipt:completion];
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
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
    if (![evaluatedObject isKindOfClass:[SKPaymentTransaction class]]) {
      return false;
    }
    return ((SKPaymentTransaction *)evaluatedObject).transactionState == SKPaymentTransactionStateRestored;
  }];
  NSArray *restoredTransactions = [transactions filteredArrayUsingPredicate:predicate];
  if (restoredTransactions.count > 0 && [self.delegate respondsToSelector:@selector(handleRestoredTransactions:)]) {
    [self.delegate handleRestoredTransactions:restoredTransactions];
  }
  
  if (transactions.count == 1) {
    [self handleTransaction:[transactions firstObject]];
  } else {
    NSArray *filteredTransactions = [self filterTransactions:transactions];
    for (SKPaymentTransaction *transaction in filteredTransactions) {
      [self handleTransaction:transaction];
    }
    
    NSArray<SKPaymentTransaction *> *excessTransactions = [transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return ![filteredTransactions containsObject:evaluatedObject];
    }]];
    
    if (excessTransactions.count > 0 && [self.delegate respondsToSelector:@selector(handleExcessTransactions:)]) {
      [self.delegate handleExcessTransactions:excessTransactions];
    }
  }
}

- (NSArray<SKPaymentTransaction *> *)sortTransactionsByDate:(NSArray<SKPaymentTransaction *> *)transactions {
  NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"transactionDate" ascending:YES];
  NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
  NSArray *sortedTransactions = [transactions sortedArrayUsingDescriptors:sortDescriptors];
  
  return sortedTransactions;
}

- (NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *)groupTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  NSMutableDictionary *groupedTransactionsMap = [NSMutableDictionary new];
  for (SKPaymentTransaction *transaction in transactions) {
    if (transaction.transactionIdentifier.length == 0) {
      continue;
    }
    
    if (!transaction.originalTransaction || transaction.originalTransaction.transactionIdentifier.length == 0) {
      groupedTransactionsMap[transaction.transactionIdentifier] = [NSMutableArray arrayWithObject:transaction];
      continue;
    }
    
    NSMutableArray *transactionsByOriginalId = groupedTransactionsMap[transaction.originalTransaction.transactionIdentifier] ?: [NSMutableArray new];
    
    [transactionsByOriginalId addObject:transaction];
    
    groupedTransactionsMap[transaction.originalTransaction.transactionIdentifier] = transactionsByOriginalId;
  }
  
  return [groupedTransactionsMap copy];
}

- (NSArray<SKPaymentTransaction *> *)filterGroupedTransactions:(NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *)groupedTransactionsMap {
  NSMutableArray<SKPaymentTransaction *> *resultTransactions = [NSMutableArray new];
  for (NSString *key in groupedTransactionsMap) {
    NSArray *groupedTransactions = groupedTransactionsMap[key];
    if (groupedTransactions.count > 1) {
      NSString *previousHandledProductId;
      
      for (SKPaymentTransaction *transaction in groupedTransactions) {
        BOOL isTheSameProductId = [previousHandledProductId isEqualToString:transaction.payment.productIdentifier];
        if (!isTheSameProductId) {
          [resultTransactions addObject:transaction];
          previousHandledProductId = transaction.payment.productIdentifier;
        }
      }
    } else {
      [resultTransactions addObjectsFromArray:groupedTransactions];
    }
  }
  
  return [resultTransactions copy];
}

- (NSArray<SKPaymentTransaction *> *)filterTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
  NSArray *sortedTransactions = [self sortTransactionsByDate:transactions];
  
  NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *groupedTransactionsMap = [self groupTransactions:sortedTransactions];
  
  NSArray *resultTransactions = [self filterGroupedTransactions:groupedTransactionsMap];
  
  return resultTransactions;
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
    case SKPaymentTransactionStateDeferred:
      [self handleDeferredTransaction:transaction];
      break;
    default:
      break;
  }
}

// MARK: - SKProductsRequestDelegate

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
  if (response.invalidProductIdentifiers.count > 0) {
    QONVERSION_LOG(@"❌ Invalid store products identifiers: %@", response.invalidProductIdentifiers);
  }
  
  BOOL autoTracked = NO;
  for (SKProduct *product in response.products) {
    [_products setValue:product forKey:product.productIdentifier];
  
    // Transactions for auto-tracking
    NSArray<SKPaymentTransaction *> *transactions = [self.processingTransactions objectForKey:product.productIdentifier];
    
    if (transactions.count > 0) {
      [self.productRequests removeObjectForKey:product.productIdentifier];
      [self.processingTransactions removeObjectForKey:product.productIdentifier];
      
      for (SKPaymentTransaction *transaction in transactions) {
        [self handleTransaction:transaction];
      }
      
      // Auto-inited requests
      SKProductsRequest *storedRequest = self.productRequests[product.productIdentifier];
      if (response.products.count == 1 && storedRequest) {
        autoTracked = YES;
      }
    }
  }
  
  if (request != self.productsRequest) {
    return;
  }
  
  self.isProductsLoaded = YES;
  
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
  }
}

- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction {
  NSString *productIdentifier = transaction.payment.productIdentifier;
  SKProduct *skProduct = _products[productIdentifier];
  
  if (skProduct) {
    if ([self.delegate respondsToSelector:@selector(handleDeferredTransaction:forProduct:)]) {
      [self.delegate handleDeferredTransaction:transaction forProduct:skProduct];
    }
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
  NSArray *transactionsArray = self.processingTransactions[productIdentifier] ?: @[];
  NSMutableArray *transactions = [transactionsArray mutableCopy];
  [transactions addObject:transaction];
  
  [self.processingTransactions setObject:[transactions copy] forKey:productIdentifier];
  NSSet<NSString *> *productSet = [NSSet setWithObject:productIdentifier];
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
