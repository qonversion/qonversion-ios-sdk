#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigSnapshot+Protected.h"
#import "QONRemoteConfigV2Models.h"

@interface QONRemoteConfigSnapshot ()
@property (nonatomic, strong, nullable) QONRemoteConfigV2Release *primaryRelease;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Release *previousRelease;
@property (nonatomic, strong, nullable) QONRemoteConfigV2Release *fallbackRelease;
@end

@implementation QONRemoteConfigSnapshot

- (instancetype)initWithPrimaryRelease:(QONRemoteConfigV2Release *)primaryRelease
                        previousRelease:(QONRemoteConfigV2Release *)previousRelease
                        fallbackRelease:(QONRemoteConfigV2Release *)fallbackRelease {
  self = [super init];
  if (self) {
    _primaryRelease = primaryRelease;
    _previousRelease = previousRelease;
    _fallbackRelease = fallbackRelease;
  }
  return self;
}

- (NSString *)releaseUID {
  return self.primaryRelease.releaseUID ?: self.previousRelease.releaseUID ?: self.fallbackRelease.releaseUID ?: @"";
}

- (NSInteger)releaseNumber {
  return self.primaryRelease ? self.primaryRelease.releaseNumber :
      (self.previousRelease ? self.previousRelease.releaseNumber : self.fallbackRelease.releaseNumber);
}

- (NSInteger)servedReleaseNumber {
  return self.primaryRelease ? self.primaryRelease.releaseNumber : 0;
}

- (NSString *)manifestContentHash {
  return self.primaryRelease.manifestContentHash ?: self.previousRelease.manifestContentHash ?:
      self.fallbackRelease.manifestContentHash ?: @"";
}

- (NSSet<NSString *> *)allKeys {
  NSMutableSet *keys = [NSMutableSet new];
  QONRemoteConfigV2Release *primary = self.primaryRelease;
  QONRemoteConfigV2Release *fallback = self.fallbackRelease;
  if (primary) [keys addObjectsFromArray:primary.entries.allKeys];
  if (fallback) [keys addObjectsFromArray:fallback.entries.allKeys];
  return [keys copy];
}

- (NSArray<NSArray *> *)candidatesForKey:(NSString *)key {
  NSMutableArray *candidates = [NSMutableArray new];
  QONRemoteConfigV2Entry *entry = self.primaryRelease.entries[key];
  if (entry && !entry.isTombstone) {
    [candidates addObject:@[entry, @(QONRemoteConfigValueSourceServer)]];
    entry = self.previousRelease.entries[key];
    if (entry && !entry.isTombstone) {
      [candidates addObject:@[entry, @(QONRemoteConfigValueSourceCache)]];
    }
  }
  entry = self.fallbackRelease.entries[key];
  if (entry && !entry.isTombstone) {
    [candidates addObject:@[entry, @(QONRemoteConfigValueSourceFallback)]];
  }
  return candidates;
}

- (QONRemoteConfigValue *)resolvedValueForEntry:(QONRemoteConfigV2Entry *)entry
                                         source:(QONRemoteConfigValueSource)source
                                          value:(id)value {
  NSData *rawData = entry.rawData;
  NSString *variationUID = entry.variationUID;
  if (!rawData || !variationUID) return nil;
  return [[QONRemoteConfigValue alloc] initWithValue:value source:source rawData:rawData
      variationUID:variationUID applyPolicy:entry.applyPolicy metadata:entry.metadata];
}

- (QONRemoteConfigValue *)rawValueForKey:(NSString *)key {
  QONRemoteConfigV2Entry *entry = self.primaryRelease.entries[key];
  QONRemoteConfigValueSource source = QONRemoteConfigValueSourceServer;
  if (!entry || entry.isTombstone) {
    entry = self.fallbackRelease.entries[key];
    source = QONRemoteConfigValueSourceFallback;
  }
  if (!entry || entry.isTombstone) return nil;
  NSData *rawData = entry.rawData;
  if (!rawData) return nil;
  id value = [NSJSONSerialization JSONObjectWithData:rawData
                                             options:NSJSONReadingFragmentsAllowed
                                               error:nil];
  if (!value) return nil;
  return [self resolvedValueForEntry:entry source:source value:value];
}

- (QONRemoteConfigValue *)valueForKey:(NSString *)key decoder:(QONRemoteConfigValueDecoder)decoder {
  if (!decoder) return nil;
  for (NSArray *candidate in [self candidatesForKey:key]) {
    QONRemoteConfigV2Entry *entry = candidate[0];
    NSData *rawData = entry.rawData;
    if (!rawData) continue;
    NSError *error = nil;
    id value = decoder([rawData copy], &error);
    if (value && !error) {
      return [self resolvedValueForEntry:entry source:[candidate[1] integerValue] value:value];
    }
  }
  return nil;
}

- (id)metadataForKey:(NSString *)key {
  return [self effectiveEntryForKey:key].metadata;
}

- (QONRemoteConfigV2Entry *)effectiveEntryForKey:(NSString *)key {
  QONRemoteConfigV2Entry *entry = self.primaryRelease.entries[key];
  if (!entry || entry.isTombstone) entry = self.fallbackRelease.entries[key];
  return entry.isTombstone ? nil : entry;
}

@end
