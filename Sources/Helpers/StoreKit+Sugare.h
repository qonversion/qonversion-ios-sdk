#import <StoreKit/StoreKit.h>

@interface SKProduct (PrettyCurrency)

@property (nonatomic, strong) NSString *prettyCurrency;

@end

@interface SKPaymentTransaction (Cancelled)

@property (nonatomic, assign) BOOL isCancelled;

@end
