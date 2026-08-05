#import "QONRemoteConfigValue.h"
#import "QONRemoteConfigSnapshot+Protected.h"

@implementation QONRemoteConfigValue

- (instancetype)initWithValue:(id)value
                       source:(QONRemoteConfigValueSource)source
                      rawData:(NSData *)rawData
                 variationUID:(NSString *)variationUID
                  applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                     metadata:(id)metadata {
  self = [super init];
  if (self) {
    _value = value;
    _source = source;
    _rawData = [rawData copy];
    _variationUID = [variationUID copy];
    _applyPolicy = applyPolicy;
    _metadata = [metadata copy];
  }
  return self;
}

@end
