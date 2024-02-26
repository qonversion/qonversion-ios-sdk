//
//  StoreKitOldWrapper.swift
//  Qonversion
//
//  Created by Suren Sarkisyan on 23.02.2024.
//

import Foundation
import StoreKit

class StoreKitOldWrapper: NSObject, StoreKitOldWrapperInterface {
    let delegate: StoreKitOldWrapperDelegate
    let paymentQueue: SKPaymentQueue
    
    var productsRequest: SKProductsRequest?
    
    init(delegate: StoreKitOldWrapperDelegate, paymentQueue: SKPaymentQueue) {
        self.delegate = delegate
        self.paymentQueue = paymentQueue
        
        super.init()
        
        paymentQueue.add(self)
    }
    
    func loadProducts(for ids:[String]) {
        let request = SKProductsRequest.init(productIdentifiers: Set(ids))
        request.delegate = self
        request.start()
        
        productsRequest = request
    }
    
    func restore() {
        paymentQueue.restoreCompletedTransactions()
    }
    
    @available(iOS 14.0, *)
    func presentCodeRedemptionSheet() {
        paymentQueue.presentCodeRedemptionSheet()
    }
    
    func purchase(product: SKProduct) {
        let payment = SKPayment(product: product)
        paymentQueue.add(payment)
    }
    
    func finish(transaction: SKPaymentTransaction) {
        guard transaction.transactionState != .purchasing else { return }
        
        paymentQueue.finishTransaction(transaction)
    }
}

extension StoreKitOldWrapper: SKPaymentTransactionObserver {
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        delegate.updatedTransactions(transactions)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        delegate.handle(restoreTransactionsError: error)
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        delegate.handleRestoreFinished()
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return delegate.shouldAdd(storePayment: payment, for: product)
    }
    
}

extension StoreKitOldWrapper: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        delegate.handle(productsResponse: response)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        guard let request = request as? SKProductsRequest else { return }
        
        delegate.productsRequestDidFail(with: error)
    }
    
}

//}
//
//- (void)paymentQueue:(nonnull SKPaymentQueue *)queue
// updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
//  NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
//    if (![evaluatedObject isKindOfClass:[SKPaymentTransaction class]]) {
//      return false;
//    }
//    return ((SKPaymentTransaction *)evaluatedObject).transactionState == SKPaymentTransactionStateRestored;
//  }];
//  NSArray *restoredTransactions = [transactions filteredArrayUsingPredicate:predicate];
//  if (restoredTransactions.count > 0 && [self.delegate respondsToSelector:@selector(handleRestoredTransactions:)]) {
//    [self.delegate handleRestoredTransactions:restoredTransactions];
//  }
//
//  if (transactions.count == 1) {
//    [self handleTransaction:[transactions firstObject]];
//  } else {
//    NSArray *filteredTransactions = [self filterTransactions:transactions];
//    for (SKPaymentTransaction *transaction in filteredTransactions) {
//      [self handleTransaction:transaction];
//    }
//
//    NSArray<SKPaymentTransaction *> *excessTransactions = [transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
//        return ![filteredTransactions containsObject:evaluatedObject];
//    }]];
//
//    if (excessTransactions.count > 0 && [self.delegate respondsToSelector:@selector(handleExcessTransactions:)]) {
//      [self.delegate handleExcessTransactions:excessTransactions];
//    }
//  }
//}
//- (void)purchaseProduct:(SKProduct *)product {
//  @synchronized (self) {
//    self->_purchasingCurrently = product.productIdentifier;
//  }
//  
//  SKPayment *payment = [SKPayment paymentWithProduct:product];
//  [[SKPaymentQueue defaultQueue] addPayment:payment];
//}
//
//- (void)presentCodeRedemptionSheet {
//#if TARGET_OS_IOS
//  if (@available(iOS 14.0, *)) {
//    [[SKPaymentQueue defaultQueue] presentCodeRedemptionSheet];
//  }
//#endif
//}
//


//// MARK: - SKPaymentTransactionObserver

//
//
//- (NSArray<SKPaymentTransaction *> *)sortTransactionsByDate:(NSArray<SKPaymentTransaction *> *)transactions {
//  NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"transactionDate" ascending:YES];
//  NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
//  NSArray *sortedTransactions = [transactions sortedArrayUsingDescriptors:sortDescriptors];
//  
//  return sortedTransactions;
//}
//
//- (NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *)groupTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
//  NSMutableDictionary *groupedTransactionsMap = [NSMutableDictionary new];
//  for (SKPaymentTransaction *transaction in transactions) {
//    if (transaction.transactionIdentifier.length == 0) {
//      continue;
//    }
//    
//    if (!transaction.originalTransaction || transaction.originalTransaction.transactionIdentifier.length == 0) {
//      groupedTransactionsMap[transaction.transactionIdentifier] = [NSMutableArray arrayWithObject:transaction];
//      continue;
//    }
//    
//    NSMutableArray *transactionsByOriginalId = groupedTransactionsMap[transaction.originalTransaction.transactionIdentifier] ?: [NSMutableArray new];
//    
//    [transactionsByOriginalId addObject:transaction];
//    
//    groupedTransactionsMap[transaction.originalTransaction.transactionIdentifier] = transactionsByOriginalId;
//  }
//  
//  return [groupedTransactionsMap copy];
//}
//
//- (NSArray<SKPaymentTransaction *> *)filterGroupedTransactions:(NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *)groupedTransactionsMap {
//  NSMutableArray<SKPaymentTransaction *> *resultTransactions = [NSMutableArray new];
//  for (NSString *key in groupedTransactionsMap) {
//    NSArray *groupedTransactions = groupedTransactionsMap[key];
//    if (groupedTransactions.count > 1) {
//      NSString *previousHandledProductId;
//      
//      for (SKPaymentTransaction *transaction in groupedTransactions) {
//        BOOL isTheSameProductId = [previousHandledProductId isEqualToString:transaction.payment.productIdentifier];
//        if (!isTheSameProductId) {
//          [resultTransactions addObject:transaction];
//          previousHandledProductId = transaction.payment.productIdentifier;
//        }
//      }
//    } else {
//      [resultTransactions addObjectsFromArray:groupedTransactions];
//    }
//  }
//  
//  return [resultTransactions copy];
//}
//
//- (NSArray<SKPaymentTransaction *> *)filterTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
//  NSArray *sortedTransactions = [self sortTransactionsByDate:transactions];
//  
//  NSDictionary<NSString *, NSArray<SKPaymentTransaction *> *> *groupedTransactionsMap = [self groupTransactions:sortedTransactions];
//  
//  NSArray *resultTransactions = [self filterGroupedTransactions:groupedTransactionsMap];
//  
//  return resultTransactions;
//}
//
//- (void)handleTransaction:(nonnull SKPaymentTransaction *)transaction {
//  switch (transaction.transactionState) {
//    case SKPaymentTransactionStatePurchasing:
//      break;
//    case SKPaymentTransactionStatePurchased:
//      [self handlePurchasedTransaction:transaction];
//      break;
//    case SKPaymentTransactionStateFailed:
//      [self handleFailedTransaction:transaction];
//      break;
//    case SKPaymentTransactionStateRestored:
//      [self handlePurchasedTransaction:transaction];
//      break;
//    case SKPaymentTransactionStateDeferred:
//      [self handleDeferredTransaction:transaction];
//      break;
//    default:
//      break;
//  }
//}
//
//// MARK: - SKProductsRequestDelegate
//
//- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
//  if (response.invalidProductIdentifiers.count > 0) {
//    QONVERSION_LOG(@"❌ Invalid store products identifiers: %@", response.invalidProductIdentifiers);
//  }
//  
//  BOOL autoTracked = NO;
//  for (SKProduct *product in response.products) {
//    [_products setValue:product forKey:product.productIdentifier];
//  
//    // Transactions for auto-tracking
//    NSArray<SKPaymentTransaction *> *transactions = [self.processingTransactions objectForKey:product.productIdentifier];
//    
//    if (transactions.count > 0) {
//      [self.productRequests removeObjectForKey:product.productIdentifier];
//      [self.processingTransactions removeObjectForKey:product.productIdentifier];
//      
//      for (SKPaymentTransaction *transaction in transactions) {
//        [self handleTransaction:transaction];
//      }
//      
//      // Auto-inited requests
//      SKProductsRequest *storedRequest = self.productRequests[product.productIdentifier];
//      if (response.products.count == 1 && storedRequest) {
//        autoTracked = YES;
//      }
//    }
//  }
//  
//  if (request != self.productsRequest) {
//    return;
//  }
//  
//  self.isProductsLoaded = YES;
//  
//  if (!autoTracked && [self.delegate respondsToSelector:@selector(handleProducts:)]) {
//    [self.delegate handleProducts:response.products];
//  }
//}
//
//// MARK: - Private
//- (void)handleFailedTransaction:(SKPaymentTransaction *)transaction {
//  NSString *productIdentifier = transaction.payment.productIdentifier;
//  SKProduct *skProduct = _products[productIdentifier];
//  [self finishTransaction:transaction];
//  
//  if (skProduct) {
//    if ([self.delegate respondsToSelector:@selector(handleFailedTransaction:forProduct:)]) {
//      [self.delegate handleFailedTransaction:transaction forProduct:skProduct];
//    }
//  }
//}
//
//- (void)handleDeferredTransaction:(SKPaymentTransaction *)transaction {
//  NSString *productIdentifier = transaction.payment.productIdentifier;
//  SKProduct *skProduct = _products[productIdentifier];
//  
//  if (skProduct) {
//    if ([self.delegate respondsToSelector:@selector(handleDeferredTransaction:forProduct:)]) {
//      [self.delegate handleDeferredTransaction:transaction forProduct:skProduct];
//    }
//  }
//}
//
//- (void)handlePurchasedTransaction:(SKPaymentTransaction *)transaction {
//  NSString *productIdentifier = transaction.payment.productIdentifier;
//  SKProduct *skProduct = _products[productIdentifier];
//  
//  if (skProduct) {
//    if ([self.delegate respondsToSelector:@selector(handlePurchasedTransaction:forProduct:)]) {
//      [self.delegate handlePurchasedTransaction:transaction forProduct:skProduct];
//    }
//    
//    return;
//  }
//  
//  [self processTransaction:transaction productIdentifier:productIdentifier];
//}
//
