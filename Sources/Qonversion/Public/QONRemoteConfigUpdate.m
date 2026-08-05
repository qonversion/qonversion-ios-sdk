#import "QONRemoteConfigUpdate.h"
#import "QONRemoteConfigSnapshot+Protected.h"

@implementation QONRemoteConfigUpdate

- (instancetype)initWithSnapshot:(QONRemoteConfigSnapshot *)snapshot
                      changedKeys:(NSSet<NSString *> *)changedKeys
                    metadataByKey:(NSDictionary<NSString *,id> *)metadataByKey {
  self = [super init];
  if (self) {
    _snapshot = snapshot;
    _changedKeys = [changedKeys copy];
    _metadataByKey = [metadataByKey copy];
  }
  return self;
}

@end
