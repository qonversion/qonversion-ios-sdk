#import "QONEntitlement.h"

@implementation QONEntitlement : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (self) {
    _entitlementID = [coder decodeObjectForKey:NSStringFromSelector(@selector(entitlementID))];
    _productID = [coder decodeObjectForKey:NSStringFromSelector(@selector(productID))];
    _isActive = [coder decodeBoolForKey:NSStringFromSelector(@selector(isActive))];
    _renewState = [coder decodeIntegerForKey:NSStringFromSelector(@selector(renewState))];
    _source = [coder decodeIntegerForKey:NSStringFromSelector(@selector(source))];
    _startedDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(startedDate))];
    _expirationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(expirationDate))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:_entitlementID forKey:NSStringFromSelector(@selector(entitlementID))];
  [coder encodeObject:_productID forKey:NSStringFromSelector(@selector(productID))];
  [coder encodeBool:_isActive forKey:NSStringFromSelector(@selector(isActive))];
  [coder encodeInteger:_renewState forKey:NSStringFromSelector(@selector(renewState))];
  [coder encodeInteger:_source forKey:NSStringFromSelector(@selector(source))];
  [coder encodeObject:_startedDate forKey:NSStringFromSelector(@selector(startedDate))];
  [coder encodeObject:_expirationDate forKey:NSStringFromSelector(@selector(expirationDate))];
}

- (NSString *)description
{
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.entitlementID];
  [description appendFormat:@"isActive=%d,\n", self.isActive];
  [description appendFormat:@"productID=%@,\n", self.productID];
  [description appendFormat:@"renewState=%@ (enum value = %li),\n", [self prettyRenewState], (long) self.renewState];
  [description appendFormat:@"source=%@ (enum value = %li),\n", [self prettySource], (long) self.source];
  [description appendFormat:@"startedDate=%@,\n", self.startedDate];
  [description appendFormat:@"expirationDate=%@,\n", self.expirationDate];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyRenewState {
  NSString *result = @"unknown";
  
  switch (self.renewState) {
    case QONEntitlementRenewStateNonRenewable:
      result = @"non renewable"; break;
    
    case QONEntitlementRenewStateWillRenew:
      result = @"will renew"; break;
    
    case QONEntitlementRenewStateCancelled:
      result = @"cancelled"; break;
      
    case QONEntitlementRenewStateBillingIssue:
      result = @"billing issue"; break;
      
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettySource {
   switch (self.source) {
     case QONEntitlementSourceUnknown:
       return @"Unknown";

     case QONEntitlementSourceAppStore:
       return @"App Store";

     case QONEntitlementSourcePlayStore:
       return @"Play Store";

     case QONEntitlementSourceStripe:
       return @"Stripe";
       
     case QONEntitlementSourceManual:
       return @"Manual";
   }
 }

@end
