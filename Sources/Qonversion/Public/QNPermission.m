#import "QNPermission.h"

@implementation QNPermission : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (self) {
    _permissionID = [coder decodeObjectForKey:NSStringFromSelector(@selector(permissionID))];
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
  [coder encodeObject:_permissionID forKey:NSStringFromSelector(@selector(permissionID))];
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
  
  [description appendFormat:@"id=%@,\n", self.permissionID];
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
    case QNPermissionRenewStateNonRenewable:
      result = @"non renewable"; break;
    
    case QNPermissionRenewStateWillRenew:
      result = @"will renew"; break;
    
    case QNPermissionRenewStateCancelled:
      result = @"cancelled"; break;
      
    case QNPermissionRenewStateBillingIssue:
      result = @"billing issue"; break;
      
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettySource {
   switch (self.source) {
     case QNPermissionSourceUnknown:
       return @"Unknown";

     case QNPermissionSourceAppStore:
       return @"App Store";

     case QNPermissionSourcePlayStore:
       return @"Play Store";

     case QNPermissionSourceStripe:
       return @"Stripe";
       
     case QNPermissionSourceManual:
       return @"Manual";
   }
 }

@end
