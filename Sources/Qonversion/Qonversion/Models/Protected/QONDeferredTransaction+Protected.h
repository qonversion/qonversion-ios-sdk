//
//  QONDeferredTransaction+Protected.h
//  Qonversion
//

#import "QONDeferredTransaction.h"
#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QONDeferredTransaction (Protected)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
+ (instancetype)transactionWithSKPaymentTransaction:(SKPaymentTransaction *)skTransaction
                                          skProduct:(SKProduct *)skProduct
                                               type:(QONDeferredTransactionType)type;
#pragma clang diagnostic pop

@end

NS_ASSUME_NONNULL_END
