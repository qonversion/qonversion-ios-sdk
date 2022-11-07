#import "QNStoreKitSugare.h"
#import "QNProduct.h"

@implementation QNProduct : NSObject

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

- (QNTrialDuration)trialDuration {
  if (_trialDuration) {
    return _trialDuration;
  }
  
  if (!self.skProduct) {
      return QNTrialDurationNotAvailable;
  }
  
  QNTrialDuration duration = QNTrialDurationNotAvailable;
  
  if (@available(iOS 11.2, macOS 10.13.2, watchOS 6.2, tvOS 11.2, *)) {
    if (self.skProduct.introductoryPrice) {
      duration = QNTrialDurationOther;
      
      SKProductPeriodUnit unit = self.skProduct.introductoryPrice.subscriptionPeriod.unit;
      NSUInteger numberOfUnits = self.skProduct.introductoryPrice.subscriptionPeriod.numberOfUnits;
      switch (unit) {
        case SKProductPeriodUnitDay:
          if (numberOfUnits == 3) {
            duration = QNTrialDurationThreeDays;
          } else if (numberOfUnits == 7) {
            duration = QNTrialDurationWeek;
          } else if (numberOfUnits == 14) {
            duration = QNTrialDurationTwoWeeks;
          }
          break;
          
        case SKProductPeriodUnitWeek:
          if (numberOfUnits == 1) {
            duration = QNTrialDurationWeek;
          } else if (numberOfUnits == 2) {
            duration = QNTrialDurationTwoWeeks;
          }
          break;
          
        case SKProductPeriodUnitMonth:
          if (numberOfUnits == 1) {
            duration = QNTrialDurationMonth;
          } else if (numberOfUnits == 2) {
            duration = QNTrialDurationTwoMonths;
          } else if (numberOfUnits == 3) {
            duration = QNTrialDurationThreeMonths;
          } else if (numberOfUnits == 6) {
            duration = QNTrialDurationSixMonths;
          }
          break;
          
        case SKProductPeriodUnitYear:
          if (numberOfUnits == 1) {
            duration = QNTrialDurationYear;
          }
          break;
          
        default:
          break;
      }
    }
  }
  
  _trialDuration = duration;
  
  return _trialDuration;
}

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.qonversionID];
  [description appendFormat:@"storeID=%@,\n", self.storeID];
  [description appendFormat:@"offeringID=%@,\n", self.offeringID];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendFormat:@"duration=%@ (enum value = %li),\n", [self prettyDuration], (long) self.duration];
  [description appendFormat:@"trial duration=%@ (enum value = %li),\n", [self prettyTrialDuration], (long) self.trialDuration];
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

- (NSString *)prettyDuration {
  NSString *result = @"unknown";
  
  switch (self.duration) {
    case QNProductDurationWeekly:
      result = @"weekly"; break;
    
    case QNProductDurationMonthly:
      result = @"monthly"; break;
    
    case QNProductDuration3Months:
      result = @"3 months"; break;
    
    case QNProductDuration6Months:
      result = @"6 months"; break;
    
    case QNProductDurationAnnual:
      result = @"annual"; break;
    
    case QNProductDurationLifetime:
      result = @"lifetime"; break;
      
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettyTrialDuration {
  NSString *result = @"unknown";
  
  switch (self.trialDuration) {
    case QNTrialDurationNotAvailable:
      result = @"not available"; break;
    
    case QNTrialDurationThreeDays:
      result = @"3 days"; break;
    
    case QNTrialDurationWeek:
      result = @"7 days"; break;
    
    case QNTrialDurationTwoWeeks:
      result = @"14 days"; break;
    
    case QNTrialDurationMonth:
      result = @"month"; break;
    
    case QNTrialDurationTwoMonths:
      result = @"two months"; break;
      
    case QNTrialDurationThreeMonths:
      result = @"three months"; break;
      
    case QNTrialDurationSixMonths:
      result = @"six months"; break;
      
    case QNTrialDurationYear:
      result = @"year"; break;
      
    case QNTrialDurationOther:
      result = @"other"; break;
      
    default:
      break;
  }
  
  return result;
}

- (NSString *)prettyType {
  NSString *result = @"unknown";
  
  switch (self.type) {
    case QNProductTypeTrial:
      result = @"trial"; break;
    
    case QNProductTypeDirectSubscription:
      result = @"direct subscription"; break;
    
    case QNProductTypeOneTime:
      result = @"one time"; break;
      
    default:
      break;
  }
  
  return result;
}

@end
