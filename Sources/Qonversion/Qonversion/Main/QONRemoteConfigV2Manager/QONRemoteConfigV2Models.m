#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigJSON.h"

NSUInteger const QONRemoteConfigV2MaximumEntryCount = 1000;
NSUInteger const QONRemoteConfigV2MaximumRawValueBytes = 64 * 1024;
NSUInteger const QONRemoteConfigV2MaximumMetadataBytes = 4 * 1024;
NSUInteger const QONRemoteConfigV2MaximumTotalValueBytes = 4 * 1024 * 1024;
NSUInteger const QONRemoteConfigV2MaximumKeyBytes = 256;
NSUInteger const QONRemoteConfigV2MaximumUIDCodePoints = 36;
NSUInteger const QONRemoteConfigV2MaximumScopeComponentBytes = 256;
int64_t const QONRemoteConfigV2MaximumSafeInteger = 9007199254740991LL;

static NSUInteger QONRemoteConfigV2CodePointCount(NSString *value) {
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger count = 0;
  const uint8_t *bytes = data.bytes;
  for (NSUInteger index = 0; index < data.length; index++) {
    if ((bytes[index] & 0xC0) != 0x80) count += 1;
  }
  return count;
}

static BOOL QONRemoteConfigV2ValidUID(NSString *value) {
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return data.length > 0 &&
      QONRemoteConfigV2CodePointCount(value) <= QONRemoteConfigV2MaximumUIDCodePoints;
}

static BOOL QONRemoteConfigV2ValidBoundedString(NSString *value, NSUInteger maximumBytes) {
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return data.length > 0 && data.length <= maximumBytes;
}

static BOOL QONRemoteConfigV2ValidSHA256(NSString *value) {
  if (value.length != 64 || ![value isEqualToString:value.lowercaseString]) return NO;
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
  return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static id QONRemoteConfigV2DeepJSONCopy(id value) {
  if (!value) return nil;
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:value
                                                 options:NSJSONWritingFragmentsAllowed
                                                   error:&error];
  if (!data || error) return nil;
  return QONRemoteConfigPortableJSONObject(data, QONRemoteConfigV2MaximumMetadataBytes);
}

@implementation QONRemoteConfigV2Scope

- (instancetype)initWithProjectKey:(NSString *)projectKey
                        environment:(NSString *)environment
                    canonicalUserID:(NSString *)canonicalUserID {
  if (!QONRemoteConfigV2ValidBoundedString(projectKey, QONRemoteConfigV2MaximumScopeComponentBytes) ||
      !QONRemoteConfigV2ValidUID(environment) ||
      !QONRemoteConfigV2ValidBoundedString(canonicalUserID, QONRemoteConfigV2MaximumScopeComponentBytes)) return nil;
  self = [super init];
  if (self) {
    _projectKey = [projectKey copy];
    _environment = [environment copy];
    _canonicalUserID = [canonicalUserID copy];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)hash { return self.projectKey.hash ^ self.environment.hash ^ self.canonicalUserID.hash; }
- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:QONRemoteConfigV2Scope.class]) return NO;
  QONRemoteConfigV2Scope *other = object;
  return [self.projectKey isEqualToString:other.projectKey] &&
      [self.environment isEqualToString:other.environment] &&
      [self.canonicalUserID isEqualToString:other.canonicalUserID];
}

@end

@implementation QONRemoteConfigV2Entry

- (instancetype)initWithTombstoneKey:(NSString *)key {
  if (!QONRemoteConfigV2ValidBoundedString(key, QONRemoteConfigV2MaximumKeyBytes)) return nil;
  self = [super init];
  if (self) {
    _key = [key copy];
    _applyPolicy = QONRemoteConfigApplyPolicyOnNextActivate;
    _tombstone = YES;
  }
  return self;
}

- (instancetype)initWithKey:(NSString *)key
                     rawData:(NSData *)rawData
                variationUID:(NSString *)variationUID
                 applyPolicy:(QONRemoteConfigApplyPolicy)applyPolicy
                    metadata:(id)metadata {
  if (!QONRemoteConfigV2ValidBoundedString(key, QONRemoteConfigV2MaximumKeyBytes) ||
      rawData.length == 0 || rawData.length > QONRemoteConfigV2MaximumRawValueBytes ||
      !QONRemoteConfigV2ValidUID(variationUID) ||
      (applyPolicy != QONRemoteConfigApplyPolicyOnNextActivate &&
       applyPolicy != QONRemoteConfigApplyPolicyImmediate)) return nil;
  if (!QONRemoteConfigPortableJSONObject(rawData, QONRemoteConfigV2MaximumRawValueBytes)) return nil;
  id metadataCopy = QONRemoteConfigV2DeepJSONCopy(metadata);
  if (metadata && !metadataCopy) return nil;
  NSData *metadataData = metadataCopy ? [NSJSONSerialization dataWithJSONObject:metadataCopy
      options:NSJSONWritingFragmentsAllowed error:nil] : nil;
  if (metadataData.length > QONRemoteConfigV2MaximumMetadataBytes) return nil;
  self = [super init];
  if (self) {
    _key = [key copy];
    _rawData = [rawData copy];
    _variationUID = [variationUID copy];
    _applyPolicy = applyPolicy;
    _metadata = metadataCopy;
    _tombstone = NO;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)contentEquals:(QONRemoteConfigV2Entry *)other {
  if (!other) return NO;
  return [self.key isEqualToString:other.key] &&
      self.isTombstone == other.isTombstone &&
      ((self.rawData == nil && other.rawData == nil) || [self.rawData isEqual:other.rawData]) &&
      ((self.variationUID == nil && other.variationUID == nil) || [self.variationUID isEqual:other.variationUID]) &&
      self.applyPolicy == other.applyPolicy &&
      ((self.metadata == nil && other.metadata == nil) || [self.metadata isEqual:other.metadata]);
}

@end

@implementation QONRemoteConfigV2Release

- (instancetype)initWithReleaseUID:(NSString *)releaseUID
                      releaseNumber:(NSInteger)releaseNumber
                manifestContentHash:(NSString *)manifestContentHash
                            entries:(NSDictionary<NSString *,QONRemoteConfigV2Entry *> *)entries {
  if (!QONRemoteConfigV2ValidUID(releaseUID) || releaseNumber <= 0 ||
      releaseNumber > QONRemoteConfigV2MaximumSafeInteger ||
      !QONRemoteConfigV2ValidSHA256(manifestContentHash) || !entries ||
      entries.count > QONRemoteConfigV2MaximumEntryCount) return nil;
  NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:entries.count];
  NSUInteger totalValueBytes = [releaseUID lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
      [manifestContentHash lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  if (totalValueBytes > QONRemoteConfigV2MaximumTotalValueBytes) return nil;
  for (id key in entries) {
    QONRemoteConfigV2Entry *entry = entries[key];
    if (![key isKindOfClass:NSString.class] || ![entry isKindOfClass:QONRemoteConfigV2Entry.class] ||
        ![key isEqualToString:entry.key]) return nil;
    id metadata = entry.metadata;
    NSData *metadataData = metadata ? [NSJSONSerialization dataWithJSONObject:metadata
        options:NSJSONWritingFragmentsAllowed error:nil] : nil;
    NSUInteger entryBytes = [entry.key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
        [entry.variationUID lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
        entry.rawData.length + metadataData.length;
    if (entryBytes > QONRemoteConfigV2MaximumTotalValueBytes - totalValueBytes) return nil;
    totalValueBytes += entryBytes;
    copy[key] = entry;
  }
  self = [super init];
  if (self) {
    _releaseUID = [releaseUID copy];
    _releaseNumber = releaseNumber;
    _manifestContentHash = [manifestContentHash copy];
    _entries = [copy copy];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)containsImmediateEntry {
  for (QONRemoteConfigV2Entry *entry in self.entries.allValues) {
    if (entry.applyPolicy == QONRemoteConfigApplyPolicyImmediate) return YES;
  }
  return NO;
}

- (BOOL)contentEquals:(QONRemoteConfigV2Release *)other {
  if (!other || ![self.releaseUID isEqualToString:other.releaseUID] ||
      self.releaseNumber != other.releaseNumber ||
      ![self.manifestContentHash isEqualToString:other.manifestContentHash] ||
      self.entries.count != other.entries.count) return NO;
  for (NSString *key in self.entries) {
    if (![self.entries[key] contentEquals:other.entries[key]]) return NO;
  }
  return YES;
}

@end

@implementation QONRemoteConfigV2State

- (instancetype)initWithCandidate:(QONRemoteConfigV2Release *)candidate
                            active:(QONRemoteConfigV2Release *)active
                          previous:(QONRemoteConfigV2Release *)previous
                       didActivate:(BOOL)didActivate {
  if ((!active && previous) || (!didActivate && (active || previous)) ||
      (candidate && active && candidate.releaseNumber < active.releaseNumber) ||
      (candidate && active && candidate.releaseNumber == active.releaseNumber &&
       ![candidate contentEquals:active]) ||
      (previous && active && previous.releaseNumber >= active.releaseNumber)) return nil;
  self = [super init];
  if (self) {
    _candidate = candidate;
    _active = active;
    _previous = previous;
    _didActivate = didActivate;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone { return self; }

@end
