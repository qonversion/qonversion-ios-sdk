#import <StoreKit/StoreKit.h>

@interface SKProduct (PrettyCurrency)

@property (nonatomic, copy, readonly) NSString *prettyCurrency;
@property (nonatomic, copy, readonly) NSString *prettyPrice;

@end

@interface SKPaymentTransaction (Cancelled)

@property (nonatomic, assign) BOOL isCancelled;

@end
