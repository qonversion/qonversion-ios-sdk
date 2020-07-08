#import "QonversionProduct.h"
#import "QonversionProduct+Protected.h"
#import "StoreKitSugare.h"

@implementation QonversionProduct : NSObject

- (instancetype)initWithCoder:(NSCoder *)coder
{
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

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:_qonversionID forKey:NSStringFromSelector(@selector(qonversionID))];
  [coder encodeObject:_storeID forKey:NSStringFromSelector(@selector(storeID))];
  [coder encodeInteger:_type forKey:NSStringFromSelector(@selector(type))];
  [coder encodeInteger:_duration forKey:NSStringFromSelector(@selector(duration))];
  [coder encodeInteger:_skProduct forKey:NSStringFromSelector(@selector(skProduct))];
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

@end
