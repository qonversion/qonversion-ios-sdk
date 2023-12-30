#import "QONEntitlement.h"
#import "QONTransaction.h"

@implementation QONEntitlement : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _entitlementID = [coder decodeObjectForKey:NSStringFromSelector(@selector(entitlementID))];
    _productID = [coder decodeObjectForKey:NSStringFromSelector(@selector(productID))];
    _isActive = [coder decodeBoolForKey:NSStringFromSelector(@selector(isActive))];
    _renewState = [coder decodeIntegerForKey:NSStringFromSelector(@selector(renewState))];
    _source = [coder decodeIntegerForKey:NSStringFromSelector(@selector(source))];
    _startedDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(startedDate))];
    _expirationDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(expirationDate))];
    _renewsCount = [coder decodeIntegerForKey:NSStringFromSelector(@selector(renewsCount))];
    _trialStartDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(trialStartDate))];
    _firstPurchaseDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(firstPurchaseDate))];
    _lastPurchaseDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(lastPurchaseDate))];
    _lastActivatedOfferCode = [coder decodeObjectForKey:NSStringFromSelector(@selector(lastActivatedOfferCode))];
    _grantType = [coder decodeIntegerForKey:NSStringFromSelector(@selector(grantType))];
    _autoRenewDisableDate = [coder decodeObjectForKey:NSStringFromSelector(@selector(autoRenewDisableDate))];
    _transactions = [coder decodeObjectForKey:NSStringFromSelector(@selector(transactions))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_entitlementID forKey:NSStringFromSelector(@selector(entitlementID))];
  [coder encodeObject:_productID forKey:NSStringFromSelector(@selector(productID))];
  [coder encodeBool:_isActive forKey:NSStringFromSelector(@selector(isActive))];
  [coder encodeInteger:_renewState forKey:NSStringFromSelector(@selector(renewState))];
  [coder encodeInteger:_source forKey:NSStringFromSelector(@selector(source))];
  [coder encodeObject:_startedDate forKey:NSStringFromSelector(@selector(startedDate))];
  [coder encodeObject:_expirationDate forKey:NSStringFromSelector(@selector(expirationDate))];
  [coder encodeInteger:_renewsCount forKey:NSStringFromSelector(@selector(renewsCount))];
  [coder encodeObject:_lastActivatedOfferCode forKey:NSStringFromSelector(@selector(lastActivatedOfferCode))];
  [coder encodeObject:_trialStartDate forKey:NSStringFromSelector(@selector(trialStartDate))];
  [coder encodeObject:_firstPurchaseDate forKey:NSStringFromSelector(@selector(firstPurchaseDate))];
  [coder encodeObject:_lastPurchaseDate forKey:NSStringFromSelector(@selector(lastPurchaseDate))];
  [coder encodeObject:_autoRenewDisableDate forKey:NSStringFromSelector(@selector(autoRenewDisableDate))];
  [coder encodeInteger:_grantType forKey:NSStringFromSelector(@selector(grantType))];
  [coder encodeObject:_transactions forKey:NSStringFromSelector(@selector(transactions))];
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.entitlementID];
  [description appendFormat:@"isActive=%d,\n", self.isActive];
  [description appendFormat:@"productID=%@,\n", self.productID];
  [description appendFormat:@"renewState=%@ (enum value = %li),\n", [self prettyRenewState], (long) self.renewState];
  [description appendFormat:@"source=%@ (enum value = %li),\n", [self prettySource], (long) self.source];
  [description appendFormat:@"startedDate=%@,\n", self.startedDate];
  [description appendFormat:@"expirationDate=%@,\n", self.expirationDate];
  [description appendFormat:@"renewsCount=%lu,\n", (unsigned long)self.renewsCount];
  [description appendFormat:@"trialStartDate=%@,\n", self.trialStartDate];
  [description appendFormat:@"firstPurchaseDate=%@,\n", self.firstPurchaseDate];
  [description appendFormat:@"lastPurchaseDate=%@,\n", self.lastPurchaseDate];
  [description appendFormat:@"lastActivatedOfferCode=%@,\n", self.lastActivatedOfferCode];
  [description appendFormat:@"grantType=%@ (enum value = %li),\n", [self prettyGrantType], (long) self.grantType];
  [description appendFormat:@"autoRenewDisableDate=%@,\n", self.autoRenewDisableDate];
  [description appendFormat:@"transactions=%@,\n", self.transactions];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyGrantType {
  NSString *result = @"purchase";
  
  switch (self.grantType) {
    case QONEntitlementGrantTypePurchase:
      result = @"purchase"; break;
    
    case QONEntitlementGrantTypeFamilySharing:
      result = @"family sharing"; break;
    
    case QONEntitlementGrantTypeOfferCode:
      result = @"offer code"; break;
      
    case QONEntitlementGrantTypeManual:
      result = @"manual"; break;
      
    default:
      break;
  }
  
  return result;
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
