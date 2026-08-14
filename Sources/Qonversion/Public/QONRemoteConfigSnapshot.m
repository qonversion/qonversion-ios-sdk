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
  QONRemoteConfigValue *resolved = nil;
  BOOL decodeRejected = NO;
  NSInteger rejectedReleaseNumber = 0;
  for (NSArray *candidate in [self candidatesForKey:key]) {
    QONRemoteConfigV2Entry *entry = candidate[0];
    NSData *rawData = entry.rawData;
    // Not a decode failure: there was nothing to hand the decoder.
    if (!rawData) continue;
    NSError *error = nil;
    QONRemoteConfigValueSource source = (QONRemoteConfigValueSource)[candidate[1] integerValue];
    id value = decoder([rawData copy], &error);
    if (value && !error) {
      resolved = [self resolvedValueForEntry:entry source:source value:value];
      break;
    }
    // The highest-priority rejection is the one worth reporting: it is the
    // release the app is actually being served and cannot read.
    if (!decodeRejected) {
      decodeRejected = YES;
      rejectedReleaseNumber = [self releaseNumberForSource:source];
    }
  }
  // Reported whether or not a lower-priority candidate saved the read: a served
  // value the app cannot decode is exactly the fault the dashboard is for, and
  // silently falling back to the cache is what hides it today.
  if (decodeRejected) [self notifyDecodeFailureForKey:key releaseNumber:rejectedReleaseNumber];
  return resolved;
}

- (NSInteger)releaseNumberForSource:(QONRemoteConfigValueSource)source {
  switch (source) {
    case QONRemoteConfigValueSourceServer:
      return self.primaryRelease.releaseNumber;
    case QONRemoteConfigValueSourceCache:
      return self.previousRelease.releaseNumber;
    case QONRemoteConfigValueSourceFallback:
      // A bundled default belongs to no server release, and the contract spells
      // that "unknown" as 0 rather than as the release that happens to serve.
      return 0;
  }
  return 0;
}

- (void)notifyDecodeFailureForKey:(NSString *)key releaseNumber:(NSInteger)releaseNumber {
  QONRemoteConfigDecodeFailureObserver observer = self.decodeFailureObserver;
  if (!observer || key.length == 0) return;
  @try {
    observer(key, releaseNumber);
  } @catch (__unused NSException *exception) {
    // Telemetry may never change what a read returns, including by throwing.
  }
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
