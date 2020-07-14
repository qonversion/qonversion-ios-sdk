#import "QonversionLaunchComposeModel.h"

@implementation QonversionLaunchComposeModel

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (self) {
    _error = [coder decodeObjectForKey:NSStringFromSelector(@selector(error))];
    _result = [coder decodeObjectForKey:NSStringFromSelector(@selector(result))];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:_error forKey:NSStringFromSelector(@selector(error))];
  [coder encodeObject:_result forKey:NSStringFromSelector(@selector(result))];
}


- (void)setResult:(QNLaunchResult *)result {
  _result = result;
}

@end
