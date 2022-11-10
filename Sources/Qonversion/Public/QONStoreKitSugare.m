#import "QONStoreKitSugare.h"

@implementation SKProduct (PrettyCurrency)

- (NSString *)prettyCurrency {
  NSString *currency = @"";
  
  if (@available(iOS 10.0, tvOS 10.0, *)) {
    currency = self.priceLocale.currencyCode;
  } else {
    NSNumberFormatter *formatter = NSNumberFormatter.new;
    [formatter setNumberStyle:NSNumberFormatterCurrencyISOCodeStyle];
    [formatter setLocale:self.priceLocale];
    currency = [formatter stringFromNumber:self.price];
  }
  
  return currency;
}

- (NSString *)prettyPrice {
  NSNumberFormatter *formatter = NSNumberFormatter.new;
  [formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
  [formatter setNumberStyle:NSNumberFormatterCurrencyStyle];
  [formatter setLocale:[self priceLocale]];
  
  return [formatter stringFromNumber:[self price]];
}

@end

@implementation SKPaymentTransaction (Cancelled)

- (BOOL)isCancelled {
  if (self.error == nil) {
    return NO;
  }
  
  if ([[self.error domain] isEqualToString:SKErrorDomain] == NO) {
    return NO;
  }
  
  if (self.error.code == SKErrorPaymentCancelled) {
    return YES;
  }
  
  return NO;
}

@end
