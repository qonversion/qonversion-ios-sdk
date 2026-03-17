//
//  QONDeferredTransaction.m
//  Qonversion
//

#import "QONDeferredTransaction.h"
#import "QONDeferredTransaction+Protected.h"
#import <StoreKit/StoreKit.h>

@interface QONDeferredTransaction ()

@property (nonatomic, copy) NSString *productId;
@property (nonatomic, copy, nullable) NSString *transactionId;
@property (nonatomic, copy, nullable) NSString *originalTransactionId;
@property (nonatomic, assign) QONDeferredTransactionType type;
@property (nonatomic, assign) double value;
@property (nonatomic, copy, nullable) NSString *currency;

@end

@implementation QONDeferredTransaction

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
+ (instancetype)transactionWithSKPaymentTransaction:(SKPaymentTransaction *)skTransaction
                                          skProduct:(SKProduct *)skProduct
                                               type:(QONDeferredTransactionType)type {
  QONDeferredTransaction *transaction = [[QONDeferredTransaction alloc] init];
  transaction.productId = skTransaction.payment.productIdentifier;
  transaction.transactionId = skTransaction.transactionIdentifier;
  transaction.originalTransactionId = skTransaction.originalTransaction.transactionIdentifier;
  transaction.type = type;
  transaction.value = skProduct.price.doubleValue;
  transaction.currency = [skProduct.priceLocale objectForKey:NSLocaleCurrencyCode];
  return transaction;
}
#pragma clang diagnostic pop

@end
