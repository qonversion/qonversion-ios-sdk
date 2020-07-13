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
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SKPaymentTransaction *> *transactions;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SKProductsRequest *> *productRequests;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, SKProduct *> *products;

@property (nonatomic, strong) NSString *purchasingCurrently;
@end

@implementation QNStoreKitService

- (instancetype)init {
  self = super.init;
  if (self) {
    _transactions = [[NSMutableDictionary alloc] init];
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

// MARK: - Private

- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction {
  // TODO
//  SKProduct *skProduct = [self productAt:transaction];
//
//  // Initialize using purchase:
//  if (skProduct && [skProduct.productIdentifier isEqualToString:transaction.payment.productIdentifier]) {
//    QNPurchaseCompletionHandler checkBlock = [self purchasingBlock];
//    run_block_on_main(checkBlock, nil, [QNUtils errorFromTransactionError:transaction.error], transaction.isCancelled);
//    return;
//  }
}

- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction {
  [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
  // TODO
  SKProduct *skProduct = nil;
  //SKProduct *skProduct = [self productAt:transaction];
  //NSString *productIdentifier = transaction.payment.productIdentifier;
  
  // Initialize using purchase:
  //if (skProduct && _purchasingCurrently && [_purchasingCurrently isEqualToString:productIdentifier]) {
    // TODO
    //[self purchase:skProduct transaction:transaction];
    return;
  //}
  
  if (skProduct) {
    // [self serviceLogPurchase:skProduct transaction:transaction];
  } else {
    // Auto-handling for analytics and integrations
    //[self.transactions setObject:transaction forKey:productIdentifier];
//    SKProductsRequest *request = [SKProductsRequest.alloc
//                                  initWithProductIdentifiers:[NSSet setWithObject:productIdentifier]];
//    
//    [self.productRequests setObject:request forKey:productIdentifier];
//    request.delegate = self;
//    [request start];
  }
}


// MARK: - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
  // TODO
  // Something gona wrong
  // Check here
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
  SKProduct *product = response.products.firstObject;
  if (!product) {
    return;
  }
  
  // Set products
  for (product in response.products) {
    if (product.productIdentifier) {
      [_products setValue:product forKey:product.productIdentifier];
      QONVERSION_LOG(@"Loaded Product %@ with price %@", product.productIdentifier, product.price);
    }
  }
  
  // Transactions for auto-tracking
  SKPaymentTransaction *transaction = [self.transactions objectForKey:product.productIdentifier];
  
  if (!transaction) {
    return;
  }
  
  [self logPurchase:product transaction:transaction];
  [self.transactions removeObjectForKey:product.productIdentifier];
  [self.productRequests removeObjectForKey:product.productIdentifier];
}

@end
