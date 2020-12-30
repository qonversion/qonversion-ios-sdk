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

- (NSString *)description {
  NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
  
  [description appendFormat:@"id=%@,\n", self.qonversionID];
  [description appendFormat:@"storeID=%@,\n", self.storeID];
  [description appendFormat:@"type=%@ (enum value = %li),\n", [self prettyType], (long) self.type];
  [description appendFormat:@"duration=%@ (enum value = %li),\n", [self prettyDuration], (long) self.duration];
  [description appendFormat:@"skProduct=%@,\n", self.skProduct];
  [description appendString:@">"];
  return description;
}

- (void)setSkProduct:(SKProduct *)skProduct {
  _skProduct = skProduct;
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
