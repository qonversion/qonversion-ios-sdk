#import "QONStoreKitSugare.h"
#import "QONProduct.h"
#import "QONSubscriptionPeriod+Protected.h"

@implementation QONProduct : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _qonversionID = [coder decodeObjectForKey:NSStringFromSelector(@selector(qonversionID))];
    _storeID = [coder decodeObjectForKey:NSStringFromSelector(@selector(storeID))];
    _type = [coder decodeIntegerForKey:NSStringFromSelector(@selector(type))];
    _duration = [coder decodeIntegerForKey:NSStringFromSelector(@selector(duration))];
    _skProduct = [coder decodeObjectForKey:NSStringFromSelector(@selector(skProduct))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_qonversionID forKey:NSStringFromSelector(@selector(qonversionID))];
  [coder encodeObject:_storeID forKey:NSStringFromSelector(@selector(storeID))];
  [coder encodeInteger:_type forKey:NSStringFromSelector(@selector(type))];
  [coder encodeInteger:_duration forKey:NSStringFromSelector(@selector(duration))];
}

- (void)setSkProduct:(SKProduct *)skProduct {
  _skProduct = skProduct;
}

- (QONSubscriptionPeriod *)trialPeriod {
  if (_trialPeriod) {
    return _trialPeriod;
  }
  
  if (self.skProduct.introductoryPrice) {
    _trialPeriod = [[QONSubscriptionPeriod alloc] initWithStoreSubscriptionPeriod:self.skProduct.introductoryPrice.subscriptionPeriod];
  }
  
  return _trialPeriod;
}

- (QONTrialDuration)trialDuration {
  if (_trialDuration) {
    return _trialDuration;
  }
  
  if (!self.skProduct) {
      return QONTrialDurationUnknown;
  }
  
  QONTrialDuration duration = QONTrialDurationUnknown;
  
  if (@available(iOS 11.2, macOS 10.13.2, watchOS 6.2, tvOS 11.2, *)) {
    if (self.skProduct.introductoryPrice) {
      duration = QONTrialDurationOther;
      
      SKProductPeriodUnit unit = self.skProduct.introductoryPrice.subscriptionPeriod.unit;
      NSUInteger numberOfUnits = self.skProduct.introductoryPrice.subscriptionPeriod.numberOfUnits;
      switch (unit) {
        case SKProductPeriodUnitDay:
          if (numberOfUnits == 3) {
            duration = QONTrialDurationThreeDays;
          } else if (numberOfUnits == 7) {
            duration = QONTrialDurationWeek;
          } else if (numberOfUnits == 14) {
            duration = QONTrialDurationTwoWeeks;
          }
          break;
          
        case SKProductPeriodUnitWeek:
          if (numberOfUnits == 1) {
            duration = QONTrialDurationWeek;
          } else if (numberOfUnits == 2) {
            duration = QONTrialDurationTwoWeeks;
          }
          break;
          
        case SKProductPeriodUnitMonth:
          if (numberOfUnits == 1) {
            duration = QONTrialDurationMonth;
          } else if (numberOfUnits == 2) {
            duration = QONTrialDurationTwoMonths;
          } else if (numberOfUnits == 3) {
            duration = QONTrialDurationThreeMonths;
          } else if (numberOfUnits == 6) {
            duration = QONTrialDurationSixMonths;
          }
          break;
          
        case SKProductPeriodUnitYear:
          if (numberOfUnits == 1) {
            duration = QONTrialDurationYear;
          }
          break;
          
        default:
          break;
      }
    } else {
      duration = QONTrialDurationNotAvailable;
    }
  }
  
  _trialDuration = duration;
  
  return _trialDuration;
}

- (QONProductType)type {
  if (_type) {
    return _type;
  }
  
  if (!self.skProduct) {
    return QONProductTypeUnknown;
  }
  
  QONProductType type = QONProductTypeUnknown;
  
  if (@available(iOS 11.2, macOS 10.13.2, watchOS 6.2, tvOS 11.2, *)) {
    if (self.skProduct.introductoryPrice && self.skProduct.introductoryPrice.paymentMode == SKProductDiscountPaymentModeFreeTrial) {
      type = QONProductTypeTrial;
    } else if (self.skProduct.subscriptionPeriod) {
      type = QONProductTypeDirectSubscription;
    } else {
      type = QONProductTypeOneTime;
    }
  }
  
  _type = type;
  
  return _type;
}

- (QONSubscriptionPeriod *)subscriptionPeriod {
  if (_subscriptionPeriod) {
    return _subscriptionPeriod;
  }
  
  if (self.skProduct.subscriptionPeriod) {
    _subscriptionPeriod = [[QONSubscriptionPeriod alloc] initWithStoreSubscriptionPeriod:self.skProduct.subscriptionPeriod];
  }
  
  return _subscriptionPeriod;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.qonversionID];
  [description appendFormat:@"storeID=%@,\n", self.storeID];
  [description appendFormat:@"offeringID=%@,\n", self.offeringID];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
  // Warning muted for linter
  [description appendFormat:@"duration=%@ (enum value = %li),\n", [self prettyDuration], (long) self.duration];
  [description appendFormat:@"trial duration=%@ (enum value = %li),\n", [self prettyTrialDuration], (long) self.trialDuration];
#pragma GCC diagnostic pop
  if (@available(iOS 11.2, macOS 10.13.2, watchOS 6.2, tvOS 11.2, *)) {
    [description appendFormat:@"subscription period=%@, \n", self.subscriptionPeriod];
    [description appendFormat:@"trial period=%@, \n", self.trialPeriod];
  }
  [description appendFormat:@"skProduct=%@,\n", self.skProduct];
  [description appendString:@">"];
  
  return [description copy];
}

- (NSString *)prettyPrice {
  if (_skProduct) {
    return _skProduct.prettyPrice;
  }
  
  return @"";
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
// Warning muted for linter
- (NSString *)prettyDuration {
  NSString *result = @"unknown";
  
  switch (self.duration) {
    case QONProductDurationWeekly:
      result = @"weekly"; break;
    
    case QONProductDurationMonthly:
      result = @"monthly"; break;
    
    case QONProductDuration3Months:
      result = @"3 months"; break;
    
    case QONProductDuration6Months:
      result = @"6 months"; break;
    
    case QONProductDurationAnnual:
      result = @"annual"; break;
    
    case QONProductDurationLifetime:
      result = @"lifetime"; break;
      
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettyTrialDuration {
  NSString *result = @"unknown";
  
  switch (self.trialDuration) {
    case QONTrialDurationNotAvailable:
      result = @"not available"; break;
    
    case QONTrialDurationThreeDays:
      result = @"3 days"; break;
    
    case QONTrialDurationWeek:
      result = @"7 days"; break;
    
    case QONTrialDurationTwoWeeks:
      result = @"14 days"; break;
    
    case QONTrialDurationMonth:
      result = @"month"; break;
    
    case QONTrialDurationTwoMonths:
      result = @"two months"; break;
      
    case QONTrialDurationThreeMonths:
      result = @"three months"; break;
      
    case QONTrialDurationSixMonths:
      result = @"six months"; break;
      
    case QONTrialDurationYear:
      result = @"year"; break;
      
    case QONTrialDurationOther:
      result = @"other"; break;
      
    default:
      break;
  }
  
  return result;
}

#pragma GCC diagnostic pop

- (NSString *)prettyType {
  NSString *result = @"unknown";
  
  switch (self.type) {
    case QONProductTypeTrial:
      result = @"trial"; break;
    
    case QONProductTypeDirectSubscription:
      result = @"direct subscription"; break;
    
    case QONProductTypeOneTime:
      result = @"one time"; break;
      
    default:
      break;
  }
  
  return result;
}

@end
