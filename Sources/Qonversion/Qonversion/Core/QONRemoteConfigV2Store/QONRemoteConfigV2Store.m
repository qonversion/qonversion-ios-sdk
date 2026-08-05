#import "QONRemoteConfigV2Store.h"
#import "QNLocalStorage.h"
#import "QONRemoteConfigJSON.h"
#import "QONRemoteConfigV2Models.h"
#import <string.h>

NSString *const QONRemoteConfigV2StorageKey = @"com.qonversion.keys.remote-config-v2-state";
NSUInteger const QONRemoteConfigV2MaximumPersistedScopes = 16;

static NSInteger const kQONRemoteConfigV2StoreSchema = 1;
static NSUInteger const kQONRemoteConfigV2MaximumEnvelopeBytes = 32 * 1024 * 1024;
static NSString *const kSchema = @"schema_version";
static NSString *const kScopes = @"scopes";
static NSString *const kScope = @"scope";
static NSString *const kState = @"state";

static BOOL QONRemoteConfigV2ExactInteger(id object, NSInteger *value) {
  if (![object isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID()) return NO;
  const char type = [object objCType][0];
  if (strchr("csiql", type)) {
    long long candidate = [object longLongValue];
    if (candidate < NSIntegerMin || candidate > NSIntegerMax) return NO;
    if (value) *value = (NSInteger)candidate;
    return YES;
  }
  if (strchr("CSILQ", type)) {
    unsigned long long candidate = [object unsignedLongLongValue];
    if (candidate > NSIntegerMax) return NO;
    if (value) *value = (NSInteger)candidate;
    return YES;
  }
  return NO;
}

static BOOL QONRemoteConfigV2ExactBoolean(id object, BOOL *value) {
  if (![object isKindOfClass:NSNumber.class]) return NO;
  if (CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID()) {
    if (value) *value = [object boolValue];
    return YES;
  }
  NSInteger integer = 0;
  if (!QONRemoteConfigV2ExactInteger(object, &integer) || (integer != 0 && integer != 1)) return NO;
  if (value) *value = integer == 1;
  return YES;
}

@interface QONRemoteConfigV2Store ()
@property (nonatomic, strong, nullable) id<QNLocalStorage> localStorage;
@property (nonatomic, copy, nullable) NSURL *fileURL;
@end

@implementation QONRemoteConfigV2Store

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  self = [super init];
  if (self) _localStorage = localStorage;
  return self;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
  if (!fileURL.isFileURL) return nil;
  self = [super init];
  if (self) _fileURL = [fileURL copy];
  return self;
}

+ (instancetype)applicationSupportStore {
  NSURL *applicationSupport = [NSFileManager.defaultManager
      URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  if (!applicationSupport) return nil;
  NSURL *directory = [[applicationSupport URLByAppendingPathComponent:@"io.qonversion" isDirectory:YES]
      URLByAppendingPathComponent:@"RemoteConfig" isDirectory:YES];
  NSURL *fileURL = [directory URLByAppendingPathComponent:@"remote-config-v2-state.plist"];
  return fileURL ? [[self alloc] initWithFileURL:fileURL] : nil;
}

- (void)clearArchive {
  @try {
    NSURL *fileURL = self.fileURL;
    if (fileURL) {
      [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil];
    } else {
      [self.localStorage removeObjectForKey:QONRemoteConfigV2StorageKey];
    }
  }
  @catch (__unused NSException *exception) {}
}

- (NSData *)archiveDataForRoot:(NSDictionary *)root {
  NSError *error = nil;
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
  if (!data || error || data.length == 0 || data.length > kQONRemoteConfigV2MaximumEnvelopeBytes) return nil;
  return data;
}

- (id)loadArchiveObjectWithStatus:(QONRemoteConfigV2StoreLoadStatus *)status {
  @try {
    NSURL *fileURL = self.fileURL;
    if (!fileURL) {
      id object = [self.localStorage loadObjectForKey:QONRemoteConfigV2StorageKey];
      if (status) *status = object ? QONRemoteConfigV2StoreLoadStatusFound
                                  : QONRemoteConfigV2StoreLoadStatusMissing;
      return object;
    }
    NSString *filePath = fileURL.path;
    if (!filePath) {
      if (status) *status = QONRemoteConfigV2StoreLoadStatusFailed;
      return nil;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:filePath]) {
      if (status) *status = QONRemoteConfigV2StoreLoadStatusMissing;
      return nil;
    }
    NSNumber *fileSize = nil;
    NSError *error = nil;
    if (![fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error] || error) {
      if (status) *status = QONRemoteConfigV2StoreLoadStatusFailed;
      return nil;
    }
    if (fileSize.unsignedLongLongValue == 0 ||
        fileSize.unsignedLongLongValue > kQONRemoteConfigV2MaximumEnvelopeBytes) {
      [self clearArchive];
      if (status) *status = QONRemoteConfigV2StoreLoadStatusMissing;
      return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:fileURL
        options:NSDataReadingMappedIfSafe error:&error];
    if (!data || error) {
      if (status) *status = QONRemoteConfigV2StoreLoadStatusFailed;
      return nil;
    }
    if (data.length == 0 || data.length > kQONRemoteConfigV2MaximumEnvelopeBytes) {
      [self clearArchive];
      if (status) *status = QONRemoteConfigV2StoreLoadStatusMissing;
      return nil;
    }
    id root = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:nil error:&error];
    if (!root || error) {
      [self clearArchive];
      if (status) *status = QONRemoteConfigV2StoreLoadStatusMissing;
      return nil;
    }
    if (status) *status = QONRemoteConfigV2StoreLoadStatusFound;
    return root;
  } @catch (__unused NSException *exception) {
    if (status) *status = QONRemoteConfigV2StoreLoadStatusFailed;
    return nil;
  }
}

- (BOOL)writeRoot:(NSDictionary *)root {
  NSData *data = [self archiveDataForRoot:root];
  if (!data) return NO;
  NSURL *fileURL = self.fileURL;
  if (fileURL) {
    NSData *previousData = [NSData dataWithContentsOfURL:fileURL options:0 error:nil];
    NSURL *directory = [fileURL URLByDeletingLastPathComponent];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory
        withIntermediateDirectories:YES attributes:nil error:&error] || error ||
        ![data writeToURL:fileURL options:NSDataWritingAtomic error:&error] || error) return NO;
    NSData *readBack = [NSData dataWithContentsOfURL:fileURL options:0 error:&error];
    if ([readBack isEqualToData:data] && !error) return YES;
    if (previousData) {
      [previousData writeToURL:fileURL options:NSDataWritingAtomic error:nil];
    } else {
      [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil];
    }
    return NO;
  }

  id previousRoot = nil;
  BOOL didAttemptStore = NO;
  @try {
    previousRoot = [self.localStorage loadObjectForKey:QONRemoteConfigV2StorageKey];
    didAttemptStore = YES;
    [self.localStorage storeObject:root forKey:QONRemoteConfigV2StorageKey];
    id readBack = [self.localStorage loadObjectForKey:QONRemoteConfigV2StorageKey];
    if ([readBack isEqual:root]) return YES;
    if (previousRoot) {
      [self.localStorage storeObject:previousRoot forKey:QONRemoteConfigV2StorageKey];
    } else {
      [self.localStorage removeObjectForKey:QONRemoteConfigV2StorageKey];
    }
  } @catch (__unused NSException *exception) {
    if (didAttemptStore) {
      @try {
        if (previousRoot) {
          [self.localStorage storeObject:previousRoot forKey:QONRemoteConfigV2StorageKey];
        } else {
          [self.localStorage removeObjectForKey:QONRemoteConfigV2StorageKey];
        }
      } @catch (__unused NSException *rollbackException) {}
    }
  }
  return NO;
}

- (NSDictionary *)scopeDictionary:(QONRemoteConfigV2Scope *)scope {
  return @{@"project": scope.projectKey, @"environment": scope.environment, @"user": scope.canonicalUserID};
}

- (QONRemoteConfigV2Scope *)scopeFromDictionary:(id)object {
  if (![object isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *dictionary = object;
  if (dictionary.count != 3 || ![dictionary[@"project"] isKindOfClass:NSString.class] ||
      ![dictionary[@"environment"] isKindOfClass:NSString.class] ||
      ![dictionary[@"user"] isKindOfClass:NSString.class]) return nil;
  NSString *project = (NSString *)dictionary[@"project"];
  NSString *environment = (NSString *)dictionary[@"environment"];
  NSString *user = (NSString *)dictionary[@"user"];
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:project
      environment:environment canonicalUserID:user];
}

- (NSDictionary *)entryDictionary:(QONRemoteConfigV2Entry *)entry {
  if (entry.isTombstone) {
    return @{@"key": entry.key, @"raw": @"", @"variation": @"",
             @"policy": @(QONRemoteConfigApplyPolicyOnNextActivate), @"metadata": @""};
  }
  NSData *rawData = entry.rawData;
  NSString *variationUID = entry.variationUID;
  if (!rawData || !variationUID) return @{};
  id metadata = entry.metadata;
  NSData *metadataData = metadata ? [NSJSONSerialization dataWithJSONObject:metadata
      options:NSJSONWritingFragmentsAllowed error:nil] : nil;
  return @{
    @"key": entry.key,
    @"raw": [rawData base64EncodedStringWithOptions:0],
    @"variation": variationUID,
    @"policy": @(entry.applyPolicy),
    @"metadata": metadataData ? [metadataData base64EncodedStringWithOptions:0] : @"",
  };
}

- (QONRemoteConfigV2Entry *)entryFromDictionary:(id)object {
  if (![object isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *dictionary = object;
  if (dictionary.count != 5 || ![dictionary[@"key"] isKindOfClass:NSString.class] ||
      ![dictionary[@"raw"] isKindOfClass:NSString.class] ||
      ![dictionary[@"variation"] isKindOfClass:NSString.class] ||
      ![dictionary[@"metadata"] isKindOfClass:NSString.class]) return nil;
  NSString *key = (NSString *)dictionary[@"key"];
  NSString *encodedRaw = (NSString *)dictionary[@"raw"];
  NSString *variationUID = (NSString *)dictionary[@"variation"];
  NSString *encodedMetadata = (NSString *)dictionary[@"metadata"];
  NSInteger policy = 0;
  if (!QONRemoteConfigV2ExactInteger(dictionary[@"policy"], &policy)) return nil;
  if (encodedRaw.length == 0 || variationUID.length == 0) {
    if (encodedRaw.length == 0 && variationUID.length == 0 && encodedMetadata.length == 0 &&
        policy == QONRemoteConfigApplyPolicyOnNextActivate) {
      return [[QONRemoteConfigV2Entry alloc] initWithTombstoneKey:key];
    }
    return nil;
  }
  NSData *raw = [[NSData alloc] initWithBase64EncodedString:encodedRaw options:0];
  if (!raw || ![[raw base64EncodedStringWithOptions:0] isEqualToString:encodedRaw]) return nil;
  id metadata = nil;
  if (encodedMetadata.length > 0) {
    NSData *metadataData = [[NSData alloc] initWithBase64EncodedString:encodedMetadata options:0];
    if (!metadataData || metadataData.length > QONRemoteConfigV2MaximumMetadataBytes ||
        ![[metadataData base64EncodedStringWithOptions:0] isEqualToString:encodedMetadata]) return nil;
    metadata = QONRemoteConfigPortableJSONObject(metadataData, QONRemoteConfigV2MaximumMetadataBytes);
    if (!metadata) return nil;
  }
  return [[QONRemoteConfigV2Entry alloc] initWithKey:key rawData:raw
      variationUID:variationUID applyPolicy:policy
      metadata:metadata];
}

- (id)releaseDictionary:(QONRemoteConfigV2Release *)release {
  if (!release) return @{};
  NSMutableArray *entries = [NSMutableArray new];
  for (NSString *key in [release.entries.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    [entries addObject:[self entryDictionary:release.entries[key]]];
  }
  return @{@"uid": release.releaseUID, @"number": @(release.releaseNumber),
      @"hash": release.manifestContentHash, @"entries": entries};
}

- (QONRemoteConfigV2Release *)releaseFromObject:(id)object validNull:(BOOL *)validNull {
  if ([object isKindOfClass:NSDictionary.class] && [object count] == 0) {
    if (validNull) *validNull = YES;
    return nil;
  }
  if (![object isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *dictionary = object;
  if (dictionary.count != 4 || ![dictionary[@"uid"] isKindOfClass:NSString.class] ||
      ![dictionary[@"hash"] isKindOfClass:NSString.class] ||
      ![dictionary[@"entries"] isKindOfClass:NSArray.class]) return nil;
  NSString *releaseUID = (NSString *)dictionary[@"uid"];
  NSString *manifestContentHash = (NSString *)dictionary[@"hash"];
  NSInteger releaseNumber = 0;
  if (!QONRemoteConfigV2ExactInteger(dictionary[@"number"], &releaseNumber)) return nil;
  NSMutableDictionary *entries = [NSMutableDictionary new];
  for (id entryObject in dictionary[@"entries"]) {
    QONRemoteConfigV2Entry *entry = [self entryFromDictionary:entryObject];
    if (!entry || entries[entry.key]) return nil;
    entries[entry.key] = entry;
  }
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:releaseUID
      releaseNumber:releaseNumber
      manifestContentHash:manifestContentHash entries:entries];
}

- (NSDictionary *)stateDictionary:(QONRemoteConfigV2State *)state {
  return @{
    @"candidate": [self releaseDictionary:state.candidate],
    @"active": [self releaseDictionary:state.active],
    @"previous": [self releaseDictionary:state.previous],
    @"did_activate": @(state.didActivate),
  };
}

- (QONRemoteConfigV2State *)stateFromDictionary:(id)object
                                 requiresRewrite:(BOOL *)requiresRewrite {
  if (![object isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *dictionary = object;
  if (dictionary.count != 4) return nil;
  BOOL didActivate = NO;
  if (!QONRemoteConfigV2ExactBoolean(dictionary[@"did_activate"], &didActivate)) return nil;
  BOOL candidateNull = NO, activeNull = NO, previousNull = NO;
  QONRemoteConfigV2Release *candidate = [self releaseFromObject:dictionary[@"candidate"] validNull:&candidateNull];
  QONRemoteConfigV2Release *active = [self releaseFromObject:dictionary[@"active"] validNull:&activeNull];
  QONRemoteConfigV2Release *previous = [self releaseFromObject:dictionary[@"previous"] validNull:&previousNull];
  BOOL rewrite = NO;
  if (!candidate && !candidateNull) rewrite = YES;
  if (!active && !activeNull) rewrite = YES;
  if (!previous && !previousNull) rewrite = YES;
  if (!didActivate && active) {
    active = nil;
    previous = nil;
    rewrite = YES;
  }
  if (!active && previous) {
    previous = nil;
    rewrite = YES;
  }
  if (candidate && active && candidate.releaseNumber < active.releaseNumber) {
    candidate = nil;
    rewrite = YES;
  }
  if (candidate && active && candidate.releaseNumber == active.releaseNumber) {
    if ([candidate contentEquals:active]) {
      candidate = active;
    } else {
      candidate = nil;
      rewrite = YES;
    }
  }
  if (previous && active && previous.releaseNumber >= active.releaseNumber) {
    previous = nil;
    rewrite = YES;
  }
  if (rewrite && !candidate && !active && !previous && !didActivate) return nil;
  if (requiresRewrite) *requiresRewrite = rewrite;
  return [[QONRemoteConfigV2State alloc] initWithCandidate:candidate active:active previous:previous
      didActivate:didActivate];
}

- (NSArray<NSDictionary *> *)validatedRecordsWithStatus:(QONRemoteConfigV2StoreLoadStatus *)status {
  QONRemoteConfigV2StoreLoadStatus archiveStatus = QONRemoteConfigV2StoreLoadStatusMissing;
  id root = [self loadArchiveObjectWithStatus:&archiveStatus];
  if (archiveStatus == QONRemoteConfigV2StoreLoadStatusFailed) {
    if (status) *status = archiveStatus;
    return nil;
  }
  if (!root) {
    if (status) *status = QONRemoteConfigV2StoreLoadStatusMissing;
    return @[];
  }
  if (![root isKindOfClass:NSDictionary.class]) { [self clearArchive]; return @[]; }
  NSDictionary *dictionary = root;
  NSInteger schema = 0;
  if (dictionary.count != 2 || !QONRemoteConfigV2ExactInteger(dictionary[kSchema], &schema) ||
      schema != kQONRemoteConfigV2StoreSchema ||
      ![dictionary[kScopes] isKindOfClass:NSArray.class]) {
    [self clearArchive];
    return @[];
  }
  NSArray *storedRecords = dictionary[kScopes];
  NSMutableSet *seenScopes = [NSMutableSet new];
  NSMutableArray<NSDictionary *> *validated = [NSMutableArray new];
  BOOL requiresRewrite = storedRecords.count > QONRemoteConfigV2MaximumPersistedScopes;
  NSUInteger admittedBytes = 0;
  NSUInteger recordBudget = kQONRemoteConfigV2MaximumEnvelopeBytes - (16 * 1024);
  for (NSUInteger position = storedRecords.count; position > 0; position--) {
    id recordObject = storedRecords[position - 1];
    if (![recordObject isKindOfClass:NSDictionary.class]) { requiresRewrite = YES; continue; }
    NSDictionary *record = recordObject;
    QONRemoteConfigV2Scope *scope = [self scopeFromDictionary:record[kScope]];
    BOOL stateRequiresRewrite = NO;
    QONRemoteConfigV2State *state = [self stateFromDictionary:record[kState]
                                               requiresRewrite:&stateRequiresRewrite];
    if (record.count != 2 || !scope || !state || [seenScopes containsObject:scope] ||
        validated.count >= QONRemoteConfigV2MaximumPersistedScopes) {
      requiresRewrite = YES;
      continue;
    }
    [seenScopes addObject:scope];
    NSDictionary *canonical = @{kScope: [self scopeDictionary:scope],
                                kState: [self stateDictionary:state]};
    NSData *recordData = [self archiveDataForRoot:canonical];
    if (!recordData || recordData.length > recordBudget - MIN(recordBudget, admittedBytes)) {
      requiresRewrite = YES;
      continue;
    }
    admittedBytes += recordData.length;
    [validated insertObject:canonical atIndex:0];
    if (stateRequiresRewrite || ![canonical isEqual:record]) requiresRewrite = YES;
  }
  NSDictionary *canonicalRoot = @{kSchema: @(kQONRemoteConfigV2StoreSchema), kScopes: validated};
  while (![self archiveDataForRoot:canonicalRoot] && validated.count > 0) {
    [validated removeObjectAtIndex:0];
    canonicalRoot = @{kSchema: @(kQONRemoteConfigV2StoreSchema), kScopes: validated};
    requiresRewrite = YES;
  }
  if (requiresRewrite) {
    if (validated.count > 0) {
      [self writeRoot:canonicalRoot];
    } else {
      [self clearArchive];
    }
  }
  if (status) *status = QONRemoteConfigV2StoreLoadStatusFound;
  return validated;
}

- (NSArray<NSDictionary *> *)boundedNewestRecords:(NSArray<NSDictionary *> *)records {
  NSUInteger recordBudget = kQONRemoteConfigV2MaximumEnvelopeBytes - (16 * 1024);
  NSUInteger admittedBytes = 0;
  NSMutableArray<NSDictionary *> *bounded = [NSMutableArray new];
  for (NSUInteger position = records.count;
       position > 0 && bounded.count < QONRemoteConfigV2MaximumPersistedScopes;
       position--) {
    NSDictionary *record = records[position - 1];
    NSData *recordData = [self archiveDataForRoot:record];
    if (!recordData || recordData.length > recordBudget - MIN(recordBudget, admittedBytes)) continue;
    admittedBytes += recordData.length;
    [bounded insertObject:record atIndex:0];
  }
  return bounded;
}

- (QONRemoteConfigV2State *)stateForScope:(QONRemoteConfigV2Scope *)scope {
  QONRemoteConfigV2State *state = nil;
  return [self loadStateForScope:scope state:&state] == QONRemoteConfigV2StoreLoadStatusFound
      ? state : nil;
}

- (QONRemoteConfigV2StoreLoadStatus)loadStateForScope:(QONRemoteConfigV2Scope *)scope
                                                state:(QONRemoteConfigV2State **)state {
  if (state) *state = nil;
  if (!scope) return QONRemoteConfigV2StoreLoadStatusMissing;
  @synchronized (self) {
    QONRemoteConfigV2StoreLoadStatus status = QONRemoteConfigV2StoreLoadStatusMissing;
    NSArray<NSDictionary *> *records = [self validatedRecordsWithStatus:&status];
    if (status == QONRemoteConfigV2StoreLoadStatusFailed) return status;
    for (NSUInteger index = 0; index < records.count; index++) {
      NSDictionary *record = records[index];
      if ([[self scopeFromDictionary:record[kScope]] isEqual:scope]) {
        QONRemoteConfigV2State *loadedState = [self stateFromDictionary:record[kState]
                                                   requiresRewrite:NULL];
        if (index + 1 < records.count) {
          NSMutableArray *promoted = [records mutableCopy];
          [promoted removeObjectAtIndex:index];
          [promoted addObject:record];
          [self writeRoot:@{kSchema: @(kQONRemoteConfigV2StoreSchema), kScopes: promoted}];
        }
        if (state) *state = loadedState;
        return QONRemoteConfigV2StoreLoadStatusFound;
      }
    }
  }
  return QONRemoteConfigV2StoreLoadStatusMissing;
}

- (BOOL)saveState:(QONRemoteConfigV2State *)state forScope:(QONRemoteConfigV2Scope *)scope {
  if (!state || !scope) return NO;
  @synchronized (self) {
    QONRemoteConfigV2StoreLoadStatus status = QONRemoteConfigV2StoreLoadStatusMissing;
    NSArray *validated = [self validatedRecordsWithStatus:&status];
    if (status == QONRemoteConfigV2StoreLoadStatusFailed) return NO;
    NSMutableArray *records = [validated mutableCopy];
    NSIndexSet *matches = [records indexesOfObjectsPassingTest:^BOOL(NSDictionary *record,
                                                                     __unused NSUInteger idx,
                                                                     __unused BOOL *stop) {
      return [[self scopeFromDictionary:record[kScope]] isEqual:scope];
    }];
    [records removeObjectsAtIndexes:matches];
    NSDictionary *newRecord = @{kScope: [self scopeDictionary:scope],
                                kState: [self stateDictionary:state]};
    if (![self archiveDataForRoot:newRecord]) return NO;
    [records addObject:newRecord];
    records = [[self boundedNewestRecords:records] mutableCopy];
    BOOL admittedNewState = [records containsObject:newRecord];
    if (!admittedNewState) return NO;
    NSDictionary *root = @{kSchema: @(kQONRemoteConfigV2StoreSchema), kScopes: records};
    while (![self archiveDataForRoot:root] && records.count > 1) {
      [records removeObjectAtIndex:0];
      root = @{kSchema: @(kQONRemoteConfigV2StoreSchema), kScopes: records};
    }
    if (![self archiveDataForRoot:root]) return NO;
    return [self writeRoot:root];
  }
}

@end
