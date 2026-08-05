//
//  QONRemoteConfigManager.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 21.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONRemoteConfigManager.h"
#import "QONRemoteConfigService.h"
#import "QONRemoteConfig.h"
#import "QONRemoteConfigList+Protected.h"
#import "QONExperiment.h"
#import "QNProductCenterManager.h"
#import "QONRemoteConfigLoadingState.h"
#import "QONRemoteConfigListRequestData.h"
#import "QNUserPropertiesManager.h"
#import "QONFallbackService.h"
#import "NSError+Sugare.h"
#import "QONFallbackObject.h"
#import "QNUtils.h"
#import "QNLocalStorage.h"
#import "QNAPIClient.h"
#import "QONRemoteConfig+Protected.h"
#import "QONRemoteConfigurationSource+Protected.h"
#import "QONExperiment+Protected.h"
#import "QONExperimentGroup+Protected.h"

static NSString *const kEmptyContextKey = @"";
static NSString *const kRemoteConfigLKGStorageKey = @"com.qonversion.keys.remote-config-lkg";
static NSString *const kRemoteConfigQonversionErrorDomain = @"com.qonversion.io";
static NSInteger const kRemoteConfigLKGSchemaVersion = 2;
static NSUInteger const kRemoteConfigLKGMaxEntries = 64;
static NSUInteger const kRemoteConfigLKGMaxBytes = 512 * 1024;
static char kRemoteConfigStateQueueKey;

static NSString *const kLKGSchemaVersion = @"schema_version";
static NSString *const kLKGEntries = @"entries";
static NSString *const kLKGProjectKey = @"project_key";
static NSString *const kLKGEffectiveAPIKey = @"effective_api_key";
static NSString *const kLKGEnvironment = @"environment";
static NSString *const kLKGUserID = @"user_id";
static NSString *const kLKGContextKey = @"context_key";
static NSString *const kLKGConfig = @"config";
static NSString *const kLKGPayload = @"payload";
static NSString *const kLKGSource = @"source";
static NSString *const kLKGIdentifier = @"identifier";
static NSString *const kLKGName = @"name";
static NSString *const kLKGType = @"type";
static NSString *const kLKGAssignmentType = @"assignment_type";
static NSString *const kLKGExperiment = @"experiment";
static NSString *const kLKGGroup = @"group";

static BOOL QONRemoteConfigIsKnownSourceType(NSInteger type) {
  switch (type) {
    case QONRemoteConfigurationSourceTypeExperimentControlGroup:
    case QONRemoteConfigurationSourceTypeExperimentTreatmentGroup:
    case QONRemoteConfigurationSourceTypeRemoteConfiguration:
      return YES;
    default:
      return NO;
  }
}

static BOOL QONRemoteConfigIsKnownAssignmentType(NSInteger type) {
  switch (type) {
    case QONRemoteConfigurationAssignmentTypeAuto:
    case QONRemoteConfigurationAssignmentTypeManual:
    case QONRemoteConfigurationAssignmentTypeFrozen:
      return YES;
    default:
      return NO;
  }
}

static BOOL QONRemoteConfigIsKnownExperimentGroupType(NSInteger type) {
  switch (type) {
    case QONExperimentGroupTypeControl:
    case QONExperimentGroupTypeTreatment:
      return YES;
    default:
      return NO;
  }
}

static BOOL QONRemoteConfigIsExactIntegralNumber(id value) {
  if (![value isKindOfClass:[NSNumber class]] ||
      CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
    return NO;
  }
  NSNumber *number = value;
  return [number isEqualToNumber:@(number.integerValue)];
}

@interface QONRemoteConfigCacheScope : NSObject

@property (nonatomic, copy) NSString *projectKey;
@property (nonatomic, copy) NSString *effectiveAPIKey;
@property (nonatomic, copy) NSString *environment;
@property (nonatomic, copy) NSString *userID;

@end

@implementation QONRemoteConfigCacheScope
@end

@interface QONRemoteConfigManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *loadingStates;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigListRequestData *> *listRequests;
@property (nonatomic, strong) QONFallbackObject *fallbackData;

// Bumped on every cache invalidation (attach/detach, user change). Loads
// capture it when they start and skip the cache write if it moved — an
// in-flight response evaluated before the invalidating event must not be
// re-cached as fresh. Completions are still delivered either way.
@property (atomic, assign) NSUInteger cacheGeneration;
// A terminal identify failure must finish every list request that crossed the
// unstable-user window, including requests whose async preflight/response
// reaches the state queue only after the immediate pending-queue drain.
@property (nonatomic, assign) NSUInteger userChangeFailureGeneration;
@property (nonatomic, strong, nullable) NSError *lastUserChangeError;
@property (nonatomic, strong, nullable) id<QNLocalStorage> localStorage;
@property (atomic, assign, readwrite) QONRemoteConfigDeliveryOrigin lastDeliveryOrigin;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *deferredUserCallbacks;

@end

@implementation QONRemoteConfigManager

- (instancetype)init {
  return [self initWithLocalStorage:nil];
}

- (instancetype)initWithLocalStorage:(id<QNLocalStorage>)localStorage {
  self = [super init];
  
  if (self) {
    _remoteConfigService = [QONRemoteConfigService new];
    _loadingStates = [NSMutableDictionary new];
    _listRequests = [NSMutableArray new];
    _fallbackService = [QONFallbackService new];
    _localStorage = localStorage;
    _lastDeliveryOrigin = QONRemoteConfigDeliveryOriginUnknown;
    _stateQueue = dispatch_queue_create("io.qonversion.remote-config-state", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_stateQueue, &kRemoteConfigStateQueueKey, (__bridge void *)self, NULL);
  }
  
  return self;
}

- (BOOL)isOnStateQueue {
  return dispatch_get_specific(&kRemoteConfigStateQueueKey) == (__bridge void *)self;
}

- (void)performStateSync:(dispatch_block_t)block {
  if ([self isOnStateQueue]) {
    block();
  } else {
    __block NSArray<dispatch_block_t> *callbacks = nil;
    dispatch_sync(self.stateQueue, ^{
      NSAssert(self.deferredUserCallbacks == nil, @"Remote Config callback collector must not be nested across state transactions");
      self.deferredUserCallbacks = [NSMutableArray new];
      block();
      callbacks = [self.deferredUserCallbacks copy];
      self.deferredUserCallbacks = nil;
    });
    // Preserve the pre-existing callback contract: cache-hit completions run
    // on the API caller's thread, and network completions run on the service
    // callback thread. Manager state is already committed and unlocked here,
    // so re-entrant SDK calls cannot deadlock the serial executor.
    for (dispatch_block_t callback in callbacks) {
      callback();
    }
  }
}

- (void)deferUserCallback:(dispatch_block_t)callback {
  if (!callback) {
    return;
  }
  NSAssert([self isOnStateQueue] && self.deferredUserCallbacks != nil,
           @"User callbacks must be deferred by an active state transaction");
  [self.deferredUserCallbacks addObject:[callback copy]];
}

- (NSString *)normalizedContextKey:(NSString *)contextKey {
  return contextKey ?: kEmptyContextKey;
}

- (NSData *)serializedJSONDataForObject:(id)object {
  if (![NSJSONSerialization isValidJSONObject:object]) {
    return nil;
  }
  return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

- (QONRemoteConfigCacheScope *)currentRemoteConfigCacheScope {
  if (!self.localStorage) {
    return nil;
  }

  QNAPIClient *apiClient = self.remoteConfigService.apiClient;
  if (apiClient.apiKey.length == 0 || apiClient.userID.length == 0) {
    return nil;
  }

  QONRemoteConfigCacheScope *scope = [QONRemoteConfigCacheScope new];
  scope.projectKey = [apiClient.apiKey copy];
  scope.effectiveAPIKey = apiClient.debug
      ? [NSString stringWithFormat:@"test_%@", apiClient.apiKey]
      : [apiClient.apiKey copy];
  scope.environment = apiClient.debug ? @"sandbox" : @"production";
  scope.userID = [apiClient.userID copy];
  return scope;
}

- (BOOL)cacheScope:(QONRemoteConfigCacheScope *)scope equalsScope:(QONRemoteConfigCacheScope *)otherScope {
  if (!scope || !otherScope) {
    return scope == otherScope;
  }

  return [scope.projectKey isEqualToString:otherScope.projectKey] &&
      [scope.effectiveAPIKey isEqualToString:otherScope.effectiveAPIKey] &&
      [scope.environment isEqualToString:otherScope.environment] &&
      [scope.userID isEqualToString:otherScope.userID];
}

- (void)clearPersistentRemoteConfigLKG {
  if (!self.localStorage) {
    return;
  }

  @try {
    [self.localStorage removeObjectForKey:kRemoteConfigLKGStorageKey];
  } @catch (__unused NSException *exception) {
    // Corrupt custom storage must never turn a Remote Config fallback into a
    // process crash. There is no useful recovery action left if removal itself
    // fails, so the archive is ignored for this request.
  }
}

- (NSArray<NSDictionary *> *)validatedLKGEntriesFromStoredRoot:(id)storedRoot invalid:(BOOL *)invalid {
  if (!storedRoot) {
    return @[];
  }
  if (![storedRoot isKindOfClass:[NSDictionary class]]) {
    if (invalid) *invalid = YES;
    return nil;
  }

  NSDictionary *root = storedRoot;
  NSNumber *version = root[kLKGSchemaVersion];
  NSArray *entries = root[kLKGEntries];
  if (![version isKindOfClass:[NSNumber class]] || version.integerValue != kRemoteConfigLKGSchemaVersion ||
      ![entries isKindOfClass:[NSArray class]] || entries.count > kRemoteConfigLKGMaxEntries ||
      ![NSJSONSerialization isValidJSONObject:root]) {
    if (invalid) *invalid = YES;
    return nil;
  }

  NSData *serializedRoot = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
  if (!serializedRoot || serializedRoot.length > kRemoteConfigLKGMaxBytes) {
    if (invalid) *invalid = YES;
    return nil;
  }

  for (id entryObject in entries) {
    if (![entryObject isKindOfClass:[NSDictionary class]]) {
      if (invalid) *invalid = YES;
      return nil;
    }
    NSDictionary *entry = entryObject;
    if (![entry[kLKGProjectKey] isKindOfClass:[NSString class]] ||
        ![entry[kLKGEffectiveAPIKey] isKindOfClass:[NSString class]] ||
        ![entry[kLKGEnvironment] isKindOfClass:[NSString class]] ||
        ![entry[kLKGUserID] isKindOfClass:[NSString class]] ||
        ![entry[kLKGContextKey] isKindOfClass:[NSString class]] ||
        ![entry[kLKGConfig] isKindOfClass:[NSDictionary class]]) {
      if (invalid) *invalid = YES;
      return nil;
    }
    if (![self remoteConfigFromStoredDictionary:entry[kLKGConfig]
                             expectedContextKey:entry[kLKGContextKey]]) {
      if (invalid) *invalid = YES;
      return nil;
    }
  }

  return entries;
}

- (NSArray<NSDictionary *> *)loadPersistentLKGEntries {
  if (!self.localStorage) {
    return @[];
  }

  id storedRoot = nil;
  @try {
    storedRoot = [self.localStorage loadObjectForKey:kRemoteConfigLKGStorageKey];
  } @catch (__unused NSException *exception) {
    [self clearPersistentRemoteConfigLKG];
    return @[];
  }

  BOOL invalid = NO;
  NSArray<NSDictionary *> *entries = [self validatedLKGEntriesFromStoredRoot:storedRoot invalid:&invalid];
  if (invalid) {
    [self clearPersistentRemoteConfigLKG];
    return @[];
  }
  return entries ?: @[];
}

- (void)storePersistentLKGEntries:(NSArray<NSDictionary *> *)entries {
  if (!self.localStorage) {
    return;
  }

  NSArray<NSDictionary *> *sourceEntries = entries ?: @[];
  NSDictionary *emptyRoot = @{
    kLKGSchemaVersion: @(kRemoteConfigLKGSchemaVersion),
    kLKGEntries: @[],
  };
  NSData *emptyRootData = [self serializedJSONDataForObject:emptyRoot];
  if (!emptyRootData || emptyRootData.length > kRemoteConfigLKGMaxBytes) {
    [self clearPersistentRemoteConfigLKG];
    return;
  }

  // Build the newest suffix in one pass. Serializing each candidate exactly
  // once avoids repeatedly encoding a multi-megabyte aggregate while evicting
  // old entries one by one. For compact JSON, replacing the empty [] in the
  // root costs the sum of entry byte lengths plus one comma per extra entry.
  NSUInteger firstCandidateIndex = sourceEntries.count > kRemoteConfigLKGMaxEntries
      ? sourceEntries.count - kRemoteConfigLKGMaxEntries
      : 0;
  NSUInteger cumulativeBytes = emptyRootData.length;
  NSMutableArray<NSDictionary *> *newestFirstEntries = [NSMutableArray new];
  for (NSUInteger index = sourceEntries.count; index > firstCandidateIndex; index--) {
    NSDictionary *entry = sourceEntries[index - 1];
    NSData *entryData = [self serializedJSONDataForObject:entry];
    if (!entryData) {
      [self clearPersistentRemoteConfigLKG];
      return;
    }
    NSUInteger separatorBytes = newestFirstEntries.count > 0 ? 1 : 0;
    NSUInteger availableBytes = kRemoteConfigLKGMaxBytes - cumulativeBytes;
    if (separatorBytes > availableBytes ||
        entryData.length > availableBytes - separatorBytes) {
      break;
    }
    [newestFirstEntries addObject:entry];
    cumulativeBytes += entryData.length + separatorBytes;
  }

  if (newestFirstEntries.count == 0) {
    [self clearPersistentRemoteConfigLKG];
    return;
  }

  NSArray<NSDictionary *> *boundedEntries = newestFirstEntries.reverseObjectEnumerator.allObjects;
  // Only Foundation property-list/JSON value classes cross the archive
  // boundary. SDK model instances are deliberately reconstructed explicitly,
  // avoiding class-name-coupled NSCoding archives across SDK upgrades.
  NSDictionary *root = @{
    kLKGSchemaVersion: @(kRemoteConfigLKGSchemaVersion),
    kLKGEntries: boundedEntries,
  };
  NSData *serializedRoot = [self serializedJSONDataForObject:root];
  if (!serializedRoot || serializedRoot.length > kRemoteConfigLKGMaxBytes) {
    [self clearPersistentRemoteConfigLKG];
    return;
  }

  @try {
    [self.localStorage storeObject:root forKey:kRemoteConfigLKGStorageKey];
  } @catch (__unused NSException *exception) {
    [self clearPersistentRemoteConfigLKG];
  }
}

- (NSDictionary *)storedDictionaryForRemoteConfig:(QONRemoteConfig *)remoteConfig
                                        contextKey:(NSString *)contextKey {
  if (!remoteConfig || !remoteConfig.source || remoteConfig.source.identifier.length == 0) {
    return nil;
  }

  NSString *normalizedContextKey = [self normalizedContextKey:contextKey];
  NSString *sourceContextKey = [self normalizedContextKey:remoteConfig.source.contextKey];
  if (![sourceContextKey isEqualToString:normalizedContextKey]) {
    return nil;
  }
  if (remoteConfig.payload && ![remoteConfig.payload isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  if (remoteConfig.payload && ![NSJSONSerialization isValidJSONObject:remoteConfig.payload]) {
    return nil;
  }
  if (!QONRemoteConfigIsKnownSourceType(remoteConfig.source.type) ||
      !QONRemoteConfigIsKnownAssignmentType(remoteConfig.source.assignmentType) ||
      (remoteConfig.experiment &&
       !QONRemoteConfigIsKnownExperimentGroupType(remoteConfig.experiment.group.type))) {
    return nil;
  }

  NSDictionary *source = @{
    kLKGIdentifier: remoteConfig.source.identifier,
    kLKGName: remoteConfig.source.name ?: @"",
    kLKGType: @(remoteConfig.source.type),
    kLKGAssignmentType: @(remoteConfig.source.assignmentType),
    kLKGContextKey: sourceContextKey,
  };

  id experiment = [NSNull null];
  if (remoteConfig.experiment) {
    QONExperimentGroup *group = remoteConfig.experiment.group;
    if (!group || remoteConfig.experiment.identifier.length == 0 || group.identifier.length == 0) {
      return nil;
    }
    experiment = @{
      kLKGIdentifier: remoteConfig.experiment.identifier,
      kLKGName: remoteConfig.experiment.name ?: @"",
      kLKGGroup: @{
        kLKGIdentifier: group.identifier,
        kLKGName: group.name ?: @"",
        kLKGType: @(group.type),
      },
    };
  }

  NSDictionary *storedConfig = @{
    kLKGPayload: remoteConfig.payload ?: [NSNull null],
    kLKGSource: source,
    kLKGExperiment: experiment,
  };
  return [NSJSONSerialization isValidJSONObject:storedConfig] ? storedConfig : nil;
}

- (QONRemoteConfig *)remoteConfigFromStoredDictionary:(NSDictionary *)storedConfig
                                    expectedContextKey:(NSString *)expectedContextKey {
  if (![storedConfig isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  id payloadObject = storedConfig[kLKGPayload];
  NSDictionary *payload = nil;
  if (payloadObject != [NSNull null]) {
    if (![payloadObject isKindOfClass:[NSDictionary class]] ||
        ![NSJSONSerialization isValidJSONObject:payloadObject]) {
      return nil;
    }
    payload = payloadObject;
  }

  NSDictionary *sourceData = storedConfig[kLKGSource];
  if (![sourceData isKindOfClass:[NSDictionary class]] ||
      ![sourceData[kLKGIdentifier] isKindOfClass:[NSString class]] ||
      [sourceData[kLKGIdentifier] length] == 0 ||
      ![sourceData[kLKGName] isKindOfClass:[NSString class]] ||
      !QONRemoteConfigIsExactIntegralNumber(sourceData[kLKGType]) ||
      !QONRemoteConfigIsExactIntegralNumber(sourceData[kLKGAssignmentType]) ||
      ![sourceData[kLKGContextKey] isKindOfClass:[NSString class]] ||
      ![sourceData[kLKGContextKey] isEqualToString:[self normalizedContextKey:expectedContextKey]]) {
    return nil;
  }

  NSString *sourceContextKey = sourceData[kLKGContextKey];
  NSInteger sourceType = [sourceData[kLKGType] integerValue];
  NSInteger assignmentType = [sourceData[kLKGAssignmentType] integerValue];
  if (!QONRemoteConfigIsKnownSourceType(sourceType) ||
      !QONRemoteConfigIsKnownAssignmentType(assignmentType)) {
    return nil;
  }
  QONRemoteConfigurationSource *source = [[QONRemoteConfigurationSource alloc]
      initWithIdentifier:sourceData[kLKGIdentifier]
                    name:sourceData[kLKGName]
                    type:sourceType
          assignmentType:assignmentType
              contextKey:sourceContextKey.length > 0 ? sourceContextKey : nil];

  QONExperiment *experiment = nil;
  id experimentObject = storedConfig[kLKGExperiment];
  if (experimentObject != [NSNull null]) {
    if (![experimentObject isKindOfClass:[NSDictionary class]]) {
      return nil;
    }
    NSDictionary *experimentData = experimentObject;
    NSDictionary *groupData = experimentData[kLKGGroup];
    if (![experimentData[kLKGIdentifier] isKindOfClass:[NSString class]] ||
        [experimentData[kLKGIdentifier] length] == 0 ||
        ![experimentData[kLKGName] isKindOfClass:[NSString class]] ||
        ![groupData isKindOfClass:[NSDictionary class]] ||
        ![groupData[kLKGIdentifier] isKindOfClass:[NSString class]] ||
        [groupData[kLKGIdentifier] length] == 0 ||
        ![groupData[kLKGName] isKindOfClass:[NSString class]] ||
        !QONRemoteConfigIsExactIntegralNumber(groupData[kLKGType])) {
      return nil;
    }
    NSInteger groupType = [groupData[kLKGType] integerValue];
    if (!QONRemoteConfigIsKnownExperimentGroupType(groupType)) {
      return nil;
    }
    QONExperimentGroup *group = [[QONExperimentGroup alloc]
        initWithIdentifier:groupData[kLKGIdentifier]
                      type:groupType
                      name:groupData[kLKGName]];
    experiment = [[QONExperiment alloc] initWithIdentifier:experimentData[kLKGIdentifier]
                                                      name:experimentData[kLKGName]
                                                     group:group];
  }

  return [[QONRemoteConfig alloc] initWithPayload:payload experiment:experiment source:source];
}

- (BOOL)entry:(NSDictionary *)entry matchesScope:(QONRemoteConfigCacheScope *)scope {
  return [entry[kLKGProjectKey] isEqualToString:scope.projectKey] &&
      [entry[kLKGEffectiveAPIKey] isEqualToString:scope.effectiveAPIKey] &&
      [entry[kLKGEnvironment] isEqualToString:scope.environment] &&
      [entry[kLKGUserID] isEqualToString:scope.userID];
}

- (BOOL)isPersistentLKGEntryWithinQuota:(NSDictionary *)entry {
  NSDictionary *singleEntryRoot = @{
    kLKGSchemaVersion: @(kRemoteConfigLKGSchemaVersion),
    kLKGEntries: @[entry],
  };
  if (![NSJSONSerialization isValidJSONObject:singleEntryRoot]) {
    return NO;
  }
  NSData *serializedRoot = [NSJSONSerialization dataWithJSONObject:singleEntryRoot options:0 error:nil];
  return serializedRoot && serializedRoot.length <= kRemoteConfigLKGMaxBytes;
}

- (void)storeServerRemoteConfig:(QONRemoteConfig *)remoteConfig
                     contextKey:(NSString *)contextKey
                          scope:(QONRemoteConfigCacheScope *)scope {
  if (!scope || !self.localStorage) {
    return;
  }
  NSString *normalizedContextKey = [self normalizedContextKey:contextKey];
  NSDictionary *storedConfig = [self storedDictionaryForRemoteConfig:remoteConfig contextKey:normalizedContextKey];
  if (!storedConfig) {
    return;
  }

  NSDictionary *newEntry = @{
    kLKGProjectKey: scope.projectKey,
    kLKGEffectiveAPIKey: scope.effectiveAPIKey,
    kLKGEnvironment: scope.environment,
    kLKGUserID: scope.userID,
    kLKGContextKey: normalizedContextKey,
    kLKGConfig: storedConfig,
  };
  // Reject one pathological payload without evicting unrelated valid entries.
  if (![self isPersistentLKGEntryWithinQuota:newEntry]) {
    return;
  }

  @synchronized (self) {
    NSMutableArray<NSDictionary *> *entries = [[self loadPersistentLKGEntries] mutableCopy];
    NSIndexSet *existing = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
      return [self entry:entry matchesScope:scope] &&
          [entry[kLKGContextKey] isEqualToString:normalizedContextKey];
    }];
    [entries removeObjectsAtIndexes:existing];
    [entries addObject:newEntry];
    [self storePersistentLKGEntries:entries];
  }
}

- (QONRemoteConfig *)persistentLKGForContextKey:(NSString *)contextKey
                                          scope:(QONRemoteConfigCacheScope *)scope {
  if (!scope || !self.localStorage) {
    return nil;
  }
  NSString *normalizedContextKey = [self normalizedContextKey:contextKey];
  @synchronized (self) {
    NSMutableArray<NSDictionary *> *entries = [[self loadPersistentLKGEntries] mutableCopy];
    for (NSUInteger index = 0; index < entries.count; index++) {
      NSDictionary *entry = entries[index];
      if ([self entry:entry matchesScope:scope] &&
          [entry[kLKGContextKey] isEqualToString:normalizedContextKey]) {
        QONRemoteConfig *config = [self remoteConfigFromStoredDictionary:entry[kLKGConfig]
                                                     expectedContextKey:normalizedContextKey];
        if (!config) {
          [self clearPersistentRemoteConfigLKG];
          return nil;
        }
        if (index + 1 < entries.count) {
          // Array order is the persisted LRU index: oldest first, newest last.
          [entries removeObjectAtIndex:index];
          [entries addObject:entry];
          [self storePersistentLKGEntries:entries];
        }
        return config;
      }
    }
  }
  return nil;
}

- (void)removePersistentLKGForContextKey:(NSString *)contextKey
                                   scope:(QONRemoteConfigCacheScope *)scope {
  if (!scope || !self.localStorage) {
    return;
  }
  NSString *normalizedContextKey = [self normalizedContextKey:contextKey];
  @synchronized (self) {
    NSMutableArray<NSDictionary *> *entries = [[self loadPersistentLKGEntries] mutableCopy];
    NSIndexSet *matches = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
      return [self entry:entry matchesScope:scope] &&
          [entry[kLKGContextKey] isEqualToString:normalizedContextKey];
    }];
    if (matches.count == 0) {
      return;
    }
    [entries removeObjectsAtIndexes:matches];
    if (entries.count == 0) {
      [self clearPersistentRemoteConfigLKG];
    } else {
      [self storePersistentLKGEntries:entries];
    }
  }
}

- (NSArray<QONRemoteConfig *> *)persistentLKGForContextKeys:(NSArray<NSString *> *)contextKeys
                                     includeEmptyContextKey:(BOOL)includeEmptyContextKey
                                                      scope:(QONRemoteConfigCacheScope *)scope {
  if (!scope || !self.localStorage) {
    return @[];
  }

  NSMutableSet<NSString *> *requestedKeys = nil;
  if (contextKeys) {
    requestedKeys = [NSMutableSet setWithArray:contextKeys];
    if (includeEmptyContextKey) {
      [requestedKeys addObject:kEmptyContextKey];
    }
  }

  NSMutableArray<QONRemoteConfig *> *configs = [NSMutableArray new];
  @synchronized (self) {
    NSArray<NSDictionary *> *entries = [self loadPersistentLKGEntries];
    NSMutableArray<NSDictionary *> *untouchedEntries = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *accessedEntries = [NSMutableArray new];
    for (NSDictionary *entry in entries) {
      if (![self entry:entry matchesScope:scope]) {
        [untouchedEntries addObject:entry];
        continue;
      }
      NSString *contextKey = entry[kLKGContextKey];
      if (requestedKeys && ![requestedKeys containsObject:contextKey]) {
        [untouchedEntries addObject:entry];
        continue;
      }
      QONRemoteConfig *config = [self remoteConfigFromStoredDictionary:entry[kLKGConfig]
                                                   expectedContextKey:contextKey];
      if (!config) {
        [self clearPersistentRemoteConfigLKG];
        return @[];
      }
      [configs addObject:config];
      [accessedEntries addObject:entry];
    }
    if (accessedEntries.count > 0) {
      [untouchedEntries addObjectsFromArray:accessedEntries];
      [self storePersistentLKGEntries:untouchedEntries];
    }
  }
  return configs;
}

- (void)replacePersistentLKGWithServerList:(QONRemoteConfigList *)remoteConfigList
                               contextKeys:(NSArray<NSString *> *)contextKeys
                    includeEmptyContextKey:(BOOL)includeEmptyContextKey
                                     scope:(QONRemoteConfigCacheScope *)scope {
  if (!scope || !self.localStorage || !remoteConfigList) {
    return;
  }

  NSMutableSet<NSString *> *replacedKeys = nil;
  if (contextKeys) {
    replacedKeys = [NSMutableSet setWithArray:contextKeys];
    if (includeEmptyContextKey) {
      [replacedKeys addObject:kEmptyContextKey];
    }
  }

  NSMutableArray<NSDictionary *> *newEntries = [NSMutableArray new];
  NSMutableSet<NSString *> *uncacheableReturnedKeys = [NSMutableSet new];
  NSMutableSet<NSString *> *cacheableReturnedKeys = [NSMutableSet new];
  for (QONRemoteConfig *config in remoteConfigList.remoteConfigs) {
    NSString *contextKey = [self normalizedContextKey:config.source.contextKey];
    if (replacedKeys && ![replacedKeys containsObject:contextKey]) {
      continue;
    }
    NSDictionary *storedConfig = [self storedDictionaryForRemoteConfig:config contextKey:contextKey];
    if (!storedConfig) {
      if (![cacheableReturnedKeys containsObject:contextKey]) {
        [uncacheableReturnedKeys addObject:contextKey];
      }
      continue;
    }
    NSDictionary *newEntry = @{
      kLKGProjectKey: scope.projectKey,
      kLKGEffectiveAPIKey: scope.effectiveAPIKey,
      kLKGEnvironment: scope.environment,
      kLKGUserID: scope.userID,
      kLKGContextKey: contextKey,
      kLKGConfig: storedConfig,
    };
    if (![self isPersistentLKGEntryWithinQuota:newEntry]) {
      if (![cacheableReturnedKeys containsObject:contextKey]) {
        [uncacheableReturnedKeys addObject:contextKey];
      }
      continue;
    }
    [cacheableReturnedKeys addObject:contextKey];
    [uncacheableReturnedKeys removeObject:contextKey];
    NSIndexSet *duplicateIndexes = [newEntries indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
      return [entry[kLKGContextKey] isEqualToString:contextKey];
    }];
    [newEntries removeObjectsAtIndexes:duplicateIndexes];
    if (newEntries.count == kRemoteConfigLKGMaxEntries) {
      NSString *droppedContextKey = newEntries.firstObject[kLKGContextKey];
      [newEntries removeObjectAtIndex:0];
      [cacheableReturnedKeys removeObject:droppedContextKey];
      [uncacheableReturnedKeys addObject:droppedContextKey];
    }
    [newEntries addObject:newEntry];
  }

  @synchronized (self) {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
    for (NSDictionary *entry in [self loadPersistentLKGEntries]) {
      BOOL sameScope = [self entry:entry matchesScope:scope];
      BOOL keyCoveredByResponse = !replacedKeys || [replacedKeys containsObject:entry[kLKGContextKey]];
      BOOL shouldPreserveUncacheableLKG = [uncacheableReturnedKeys containsObject:entry[kLKGContextKey]];
      BOOL shouldReplace = sameScope && keyCoveredByResponse && !shouldPreserveUncacheableLKG;
      if (!shouldReplace) {
        [entries addObject:entry];
      }
    }
    [entries addObjectsFromArray:newEntries];
    [self storePersistentLKGEntries:entries];
  }
}

- (void)handlePendingRequests {
  if (![self isOnStateQueue]) {
    [self performStateSync:^{
      [self handlePendingRequests];
    }];
    return;
  }

  if ([self.productCenterManager isUserStable]) {
    // A successful identity boundary supersedes the previous terminal error;
    // new requests may now replay against the stable scope.
    self.lastUserChangeError = nil;
  }

  for (NSString *contextKey in self.loadingStates) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState && loadingState.completions.count > 0) {
      [self resumeRemoteConfigLoadForContextKey:contextKey loadingState:loadingState];
    }
  }

  NSArray<QONRemoteConfigListRequestData *> *requestsToSend = [self.listRequests copy];
  [self.listRequests removeAllObjects];

  for (QONRemoteConfigListRequestData *listRequest in requestsToSend) {
    if (listRequest.contextKeys) {
      [self obtainRemoteConfigListWithContextKeys:listRequest.contextKeys includeEmptyContextKey:listRequest.includeEmptyContextKey completion:listRequest.completion];
    } else {
      [self obtainRemoteConfigList:listRequest.completion];
    }
  }
}

- (void)userChangingRequestFailedWithError:(NSError *)error {
  if (![self isOnStateQueue]) {
    [self performStateSync:^{
      [self userChangingRequestFailedWithError:error];
    }];
    return;
  }

  self.userChangeFailureGeneration += 1;
  self.lastUserChangeError = error;

  NSArray<QONRemoteConfigListRequestData *> *pendingListRequests = [self.listRequests copy];
  [self.listRequests removeAllObjects];

  for (NSString *contextKey in self.loadingStates) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState) {
      // The only drain that bypasses fireRemoteConfig — consume the retry
      // stash here too, or a leftover masks a later unrelated failure as a
      // stale success. Cleared before the drain so a re-entrant path cannot
      // re-read it.
      loadingState.retryBaseline = nil;
      [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
    }
  }

  for (QONRemoteConfigListRequestData *listRequest in pendingListRequests) {
    [self deferUserCallback:^{
      listRequest.completion(nil, error);
    }];
  }
}

// Public cache invalidation seam (DEV-1236 B4). Deliberately synchronous: the
// same-uid identify path relies on invalidate-then-replay ordering. All state
// transitions share one serial executor, so an identity mutation cannot land
// between an in-flight response's scope check and completion delivery.
- (void)invalidateRemoteConfigsCache {
  [self performStateSync:^{
    [self invalidateLoadedConfigs];
  }];
}

- (void)userHasBeenChanged {
  [self performStateSync:^{
    self.lastUserChangeError = nil;
    [self bumpCacheGeneration];
    [self replaceLoadingStatesPreservingPendingCompletions];
  }];
}

- (void)userHasBeenChangedToUserID:(NSString *)userID {
  [self performStateSync:^{
    self.lastUserChangeError = nil;
    // QNAPIClient identity and the manager's scope boundary are one atomic
    // state transition. No response can observe a new API uid with the old
    // loading-state map (or the inverse).
    [self.remoteConfigService.apiClient setUserID:userID];
    [self bumpCacheGeneration];
    [self replaceLoadingStatesPreservingPendingCompletions];
  }];
}

- (void)replaceLoadingStatesPreservingPendingCompletions {
  NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *newStates = [NSMutableDictionary new];
  [self.loadingStates enumerateKeysAndObjectsUsingBlock:^(NSString *contextKey, QONRemoteConfigLoadingState *oldState, BOOL *stop) {
    if (oldState.completions.count == 0) {
      return;
    }
    QONRemoteConfigLoadingState *newState = [QONRemoteConfigLoadingState new];
    [newState.completions addObjectsFromArray:oldState.completions];
    [oldState.completions removeAllObjects];
    newStates[contextKey] = newState;
  }];
  self.loadingStates = newStates;
}

// Keep the increment atomic even for any future internal call site that is not
// yet confined to the state executor.
- (void)bumpCacheGeneration {
  @synchronized (self) {
    self.cacheGeneration += 1;
  }
}

- (void)obtainRemoteConfigWithContextKey:(NSString * _Nullable)contextKey completion:(QONRemoteConfigCompletionHandler)completion {
  if (![self isOnStateQueue]) {
    [self performStateSync:^{
      [self obtainRemoteConfigWithContextKey:contextKey completion:completion];
    }];
    return;
  }

  QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
  if (loadingState == nil) {
    loadingState = [QONRemoteConfigLoadingState new];
    self.loadingStates[contextKey ?: kEmptyContextKey] = loadingState;
  }
  [loadingState.completions addObject:completion];

  BOOL isUserStable = [self.productCenterManager isUserStable];
  if (!isUserStable || loadingState.isInProgress) {
    return;
  }

  [self resumeRemoteConfigLoadForContextKey:contextKey loadingState:loadingState];
}

- (void)resumeRemoteConfigLoadForContextKey:(NSString *)contextKey
                               loadingState:(QONRemoteConfigLoadingState *)loadingState {
  if (loadingState.completions.count == 0 || loadingState.isInProgress ||
      ![self.productCenterManager isUserStable]) {
    return;
  }

  if (loadingState.loadedConfig) {
    // The cached config is served as is, but properties set right before this
    // call must still reach the server — otherwise a cache hit swallows both
    // the property flush and the request.
    [self.userPropertiesManager forceSendProperties:nil];
    if (![self.productCenterManager isUserStable]) {
      return;
    }
    QONRemoteConfig *cachedConfig = loadingState.loadedConfig;
    // A retry resolved by a warm cache consumes its stashed baseline — a
    // leftover stash must not resurface on a later, unrelated failure.
    loadingState.retryBaseline = nil;
    self.lastDeliveryOrigin = QONRemoteConfigDeliveryOriginMemory;
    // Queued completions can be stranded on a warm state (e.g. a list load
    // re-caches a key whose superseded single-key load was re-issued, or a
    // completion queued while the user was unstable meets a warm cache on
    // replay) — drain them together with the direct caller, or they never
    // fire at all.
    [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:cachedConfig error:nil];
    return;
  }

  [self startRemoteConfigLoadForContextKey:contextKey loadingState:loadingState];
}

- (QONRemoteConfigLoadingState *)movePendingCompletionsFromLoadingState:(QONRemoteConfigLoadingState *)oldState
                                                             contextKey:(NSString *)contextKey {
  QONRemoteConfigLoadingState *liveState = [self loadingStateForContextKey:contextKey];
  if (liveState == oldState || liveState == nil) {
    liveState = [QONRemoteConfigLoadingState new];
    self.loadingStates[contextKey ?: kEmptyContextKey] = liveState;
  }
  if (oldState.completions.count > 0) {
    [liveState.completions addObjectsFromArray:oldState.completions];
    [oldState.completions removeAllObjects];
  }
  return liveState;
}

- (void)startRemoteConfigLoadForContextKey:(NSString *)contextKey
                              loadingState:(QONRemoteConfigLoadingState *)loadingState {
  loadingState.isInProgress = YES;
  NSUInteger generationAtStart = self.cacheGeneration;
  QONRemoteConfigCacheScope *scopeAtStart = [self currentRemoteConfigCacheScope];

  __block __weak QONRemoteConfigManager *weakSelf = self;

  [self.userPropertiesManager forceSendProperties:^{
    [weakSelf performStateSync:^{
      QONRemoteConfigCacheScope *scopeBeforeRequest = [weakSelf currentRemoteConfigCacheScope];
      BOOL userBecameUnstable = ![weakSelf.productCenterManager isUserStable];
      BOOL preflightScopeChanged = ![weakSelf cacheScope:scopeAtStart equalsScope:scopeBeforeRequest];
      BOOL preflightStateOrphaned = [weakSelf loadingStateForContextKey:contextKey] != loadingState;
      if (userBecameUnstable || preflightScopeChanged || preflightStateOrphaned) {
        loadingState.isInProgress = NO;
        QONRemoteConfigLoadingState *liveState = loadingState;
        if (preflightScopeChanged || preflightStateOrphaned) {
          liveState = [weakSelf movePendingCompletionsFromLoadingState:loadingState contextKey:contextKey];
        }
        // resumeRemoteConfigLoad... keeps the waiters live while identity is
        // unstable and starts exactly one request once handlePendingRequests
        // observes a stable user.
        [weakSelf resumeRemoteConfigLoadForContextKey:contextKey loadingState:liveState];
        return;
      }

      [weakSelf.remoteConfigService loadRemoteConfig:contextKey completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
        [weakSelf performStateSync:^{
          loadingState.isInProgress = NO;

          // A response that started for an old identity/project (or whose loading
          // state was orphaned by userHasBeenChanged) must never cross that scope
          // boundary. Carry both the initiating caller and queued waiters into one
          // fresh request for the current identity instead.
          QONRemoteConfigCacheScope *currentScope = [weakSelf currentRemoteConfigCacheScope];
          BOOL userBecameUnstable = ![weakSelf.productCenterManager isUserStable];
          BOOL scopeChanged = ![weakSelf cacheScope:scopeAtStart equalsScope:currentScope];
          BOOL stateOrphaned = [weakSelf loadingStateForContextKey:contextKey] != loadingState;
          if (userBecameUnstable || scopeChanged || stateOrphaned) {
            QONRemoteConfigLoadingState *liveState = loadingState;
            if (scopeChanged || stateOrphaned) {
              liveState = [weakSelf movePendingCompletionsFromLoadingState:loadingState contextKey:contextKey];
            }
            [weakSelf resumeRemoteConfigLoadForContextKey:contextKey loadingState:liveState];
            return;
          }

          if (error) {
            if (error.shouldFireFallback) {
              QONRemoteConfig *diskLKG = [weakSelf persistentLKGForContextKey:contextKey scope:scopeAtStart];
              if (diskLKG) {
                QONVERSION_LOG(@"⚠️ Serving disk last-known-good remote config for context key '%@' after a transient refresh failure (%@)", contextKey ?: @"", error.localizedDescription);
                [weakSelf fireRemoteConfig:diskLKG contextKey:contextKey loadingState:loadingState error:nil generation:generationAtStart deliveryOrigin:QONRemoteConfigDeliveryOriginDiskLastKnownGood scope:scopeAtStart];
                return;
              }
              [weakSelf actualizeFallbackData];
              QONRemoteConfig *fallbackConfig;
              if (contextKey.length == 0) {
                fallbackConfig = [weakSelf.fallbackData.remoteConfigList remoteConfigForEmptyContextKey];
              } else {
                fallbackConfig = [weakSelf.fallbackData.remoteConfigList remoteConfigForContextKey:contextKey];
              }

              if (fallbackConfig) {
                // The only signal a developer gets that this is not a fresh
                // targeting evaluation — a silently served bundle would let a
                // stale-config loop ship unnoticed.
                QONVERSION_LOG(@"⚠️ Serving the bundled fallback remote config for context key '%@' — not a fresh targeting evaluation (%@)", contextKey ?: @"", error.localizedDescription);
                [weakSelf fireRemoteConfig:fallbackConfig contextKey:contextKey loadingState:loadingState error:nil generation:generationAtStart deliveryOrigin:QONRemoteConfigDeliveryOriginBundle scope:scopeAtStart];
              } else {
                [weakSelf fireRemoteConfig:nil contextKey:contextKey loadingState:loadingState error:error generation:generationAtStart deliveryOrigin:QONRemoteConfigDeliveryOriginUnknown scope:scopeAtStart];
              }
            } else {
              if ([error.domain isEqualToString:kRemoteConfigQonversionErrorDomain] &&
                  error.code == QONErrorCodeRemoteConfigurationNotAvailable) {
                // A healthy server has authoritatively said this context no longer
                // has a config. Keeping an older disk entry would resurrect a
                // removed assignment during the next outage.
                [weakSelf removePersistentLKGForContextKey:contextKey scope:scopeAtStart];
              }
              [weakSelf fireRemoteConfig:nil contextKey:contextKey loadingState:loadingState error:error generation:generationAtStart deliveryOrigin:QONRemoteConfigDeliveryOriginUnknown scope:scopeAtStart];
            }
          } else {
            [weakSelf fireRemoteConfig:remoteConfig contextKey:contextKey loadingState:loadingState error:nil generation:generationAtStart deliveryOrigin:QONRemoteConfigDeliveryOriginServer scope:scopeAtStart];
          }
        }];
      }];
    }];
  }];
}

- (void)fireRemoteConfig:(QONRemoteConfig *)remoteConfig
               contextKey:(NSString *)contextKey
             loadingState:(QONRemoteConfigLoadingState *)loadingState
                    error:(NSError *)error
               generation:(NSUInteger)generation
           deliveryOrigin:(QONRemoteConfigDeliveryOrigin)deliveryOrigin
                    scope:(QONRemoteConfigCacheScope *)scope {
  if (![self.productCenterManager isUserStable]) {
    // The response callback crossed into an identity window after its first
    // boundary check. Keep every completion live; handlePendingRequests will
    // replay them once the identity is stable again.
    [self resumeRemoteConfigLoadForContextKey:contextKey loadingState:loadingState];
    return;
  }
  if (error) {
    QONRemoteConfig *baseline = loadingState.retryBaseline;
    loadingState.retryBaseline = nil;
    if (baseline && error.shouldFireFallback) {
      // A failed retry of a superseded load degrades to the baseline — a
      // real user-specific evaluation seconds old — for everyone, including
      // callers who joined during the retry window. Authoritative client
      // errors must propagate instead of being hidden by a stale evaluation.
      self.lastDeliveryOrigin = QONRemoteConfigDeliveryOriginRetryBaseline;
      [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:baseline error:nil];
      return;
    }
    [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:nil error:error];
    return;
  }

  if (deliveryOrigin == QONRemoteConfigDeliveryOriginDiskLastKnownGood ||
      deliveryOrigin == QONRemoteConfigDeliveryOriginBundle) {
    // The bundled fallback is a local last-resort payload, not a fresh
    // targeting evaluation — deliver it without caching so the next call
    // retries the network instead of pinning the fallback until the next
    // invalidation. No re-issue either: the network just failed. A stashed
    // retry baseline outranks the bundle: a real user-specific evaluation
    // seconds old beats shipped-in-binary defaults.
    QONRemoteConfig *baseline = loadingState.retryBaseline;
    loadingState.retryBaseline = nil;
    QONRemoteConfig *result = baseline ?: remoteConfig;
    self.lastDeliveryOrigin = baseline ? QONRemoteConfigDeliveryOriginRetryBaseline : deliveryOrigin;
    [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:result error:nil];
    return;
  }

  // A successful (or delivered-as-is) response supersedes any stashed baseline.
  loadingState.retryBaseline = nil;
  self.lastDeliveryOrigin = deliveryOrigin;
  NSUInteger currentGeneration = self.cacheGeneration;
  if (generation == currentGeneration) {
    // Cache only when no invalidation happened while the load was in flight —
    // a superseded evaluation must not be re-cached as fresh.
    if (deliveryOrigin == QONRemoteConfigDeliveryOriginServer) {
      [self storeServerRemoteConfig:remoteConfig contextKey:contextKey scope:scope];
    }
    loadingState.loadedConfig = remoteConfig;
  } else if ([self loadingStateForContextKey:contextKey] == loadingState &&
             loadingState.loadedConfig) {
    // Another current-generation request (most notably a list request) may
    // have warmed this same state while the superseded single-key response
    // was in flight. That value has already crossed the current generation
    // and scope checks, so it is fresher than this response. Serve every
    // waiter from it instead of issuing a redundant request and leaving the
    // queue dependent on a network completion nobody needed.
    loadingState.retryBaseline = nil;
    self.lastDeliveryOrigin = QONRemoteConfigDeliveryOriginMemory;
    [self executeRemoteConfigCompletionsWithContextKey:contextKey
                                          remoteConfig:loadingState.loadedConfig
                                                 error:nil];
    return;
  } else if ([self loadingStateForContextKey:contextKey] == loadingState &&
             loadingState.reissuedForGeneration != currentGeneration) {
    // The cache was invalidated while this load was in flight, so this
    // evaluation is already superseded. Re-issue the load once so the waiters
    // receive a fresh evaluation instead of the stale one. The state must
    // still be live: a user switch replaces the map, and an orphaned state
    // must not fire a request nobody awaits. All callers live in
    // loadingState.completions, so the same state can be
    // retried without snapshot/wrapper duplication. The superseded (but valid)
    // evaluation remains a baseline: a failed retry degrades to it instead of
    // surfacing an error. The generation cap guards a concurrent re-entry; one
    // load, hence one superseded response, per invalidation.
    loadingState.reissuedForGeneration = currentGeneration;
    // The stash makes the never-worse guarantee uniform: the retry's failure
    // handlers prefer it over both the error and the bundled fallback,
    // reaching late joiners queued during the retry window too.
    loadingState.retryBaseline = remoteConfig;
    [self startRemoteConfigLoadForContextKey:contextKey loadingState:loadingState];
    return;
  }
  [self executeRemoteConfigCompletionsWithContextKey:contextKey remoteConfig:remoteConfig error:nil];
}

- (void)enqueueRemoteConfigListRequestWithContextKeys:(NSArray<NSString *> *)contextKeys
                                includeEmptyContextKey:(BOOL)includeEmptyContextKey
                                            completion:(QONRemoteConfigListCompletionHandler)completion {
  QONRemoteConfigListRequestData *requestData = contextKeys
      ? [[QONRemoteConfigListRequestData alloc] initWithContextKeys:contextKeys
                                            includeEmptyContextKey:includeEmptyContextKey
                                                        completion:completion]
      : [[QONRemoteConfigListRequestData alloc] initWithCompletion:completion];
  [self.listRequests addObject:requestData];
}

- (BOOL)failRemoteConfigListRequestWithLastUserChangeError:(QONRemoteConfigListCompletionHandler)completion {
  NSError *error = self.lastUserChangeError;
  if (!error) {
    return NO;
  }
  [self deferUserCallback:^{
    completion(nil, error);
  }];
  return YES;
}

- (BOOL)failRemoteConfigListRequestIfUserChangeFailedSince:(NSUInteger)failureGeneration
                                                completion:(QONRemoteConfigListCompletionHandler)completion {
  if (self.userChangeFailureGeneration == failureGeneration) {
    return NO;
  }
  return [self failRemoteConfigListRequestWithLastUserChangeError:completion];
}

- (void)obtainRemoteConfigListWithContextKeys:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion {
  if (![self isOnStateQueue]) {
    [self performStateSync:^{
      [self obtainRemoteConfigListWithContextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey completion:completion];
    }];
    return;
  }

  NSUInteger userChangeFailureGenerationAtStart = self.userChangeFailureGeneration;

  if (![self.productCenterManager isUserStable]) {
    if ([self failRemoteConfigListRequestWithLastUserChangeError:completion]) {
      return;
    }
    [self enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                 includeEmptyContextKey:includeEmptyContextKey
                                             completion:completion];
    return;
  }

  NSMutableArray *allKeys = [contextKeys mutableCopy];
  if (includeEmptyContextKey) {
    [allKeys addObject:kEmptyContextKey];
  }
  NSMutableArray<QONRemoteConfig *> *configs = [NSMutableArray new];
  for (NSString *contextKey in allKeys) {
    QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
    if (loadingState && loadingState.loadedConfig) {
      [configs addObject:loadingState.loadedConfig];
    } else {
      break;
    }
  }

  if (configs.count == allKeys.count) {
    // Same as the single-key cache hit: serve the cached list, but flush
    // pending properties so they are not swallowed by the hit. Gated on user
    // stability (parity with the single-key path, which checks stability before
    // its cache hit) so the flush cannot POST mid-identify to a switching uid.
    if (![self.productCenterManager isUserStable]) {
      [self enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                   includeEmptyContextKey:includeEmptyContextKey
                                               completion:completion];
      return;
    }
    [self.userPropertiesManager forceSendProperties:nil];
    if (![self.productCenterManager isUserStable]) {
      [self enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                   includeEmptyContextKey:includeEmptyContextKey
                                               completion:completion];
      return;
    }
    self.lastDeliveryOrigin = QONRemoteConfigDeliveryOriginMemory;
    QONRemoteConfigList *remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:configs];
    [self deferUserCallback:^{
      completion(remoteConfigList, nil);
    }];
    return;
  }

  __block __weak QONRemoteConfigManager *weakSelf = self;
  QONRemoteConfigCacheScope *scopeAtStart = [self currentRemoteConfigCacheScope];
  NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *stateMapAtStart = self.loadingStates;
  
  [self.userPropertiesManager forceSendProperties:^{
    [weakSelf performStateSync:^{
      if ([weakSelf failRemoteConfigListRequestIfUserChangeFailedSince:userChangeFailureGenerationAtStart completion:completion]) {
        return;
      }
      QONRemoteConfigCacheScope *currentScope = [weakSelf currentRemoteConfigCacheScope];
      if (![weakSelf.productCenterManager isUserStable]) {
        [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                         includeEmptyContextKey:includeEmptyContextKey
                                                     completion:completion];
        return;
      }
      if (![weakSelf cacheScope:scopeAtStart equalsScope:currentScope] || stateMapAtStart != weakSelf.loadingStates) {
        [weakSelf obtainRemoteConfigListWithContextKeys:contextKeys
                                includeEmptyContextKey:includeEmptyContextKey
                                            completion:completion];
        return;
      }
      QONRemoteConfigListCompletionHandler completionWrapper = [weakSelf remoteConfigListCompletionWrapper:completion contextKeys:contextKeys includeEmptyContextKey:includeEmptyContextKey scope:scopeAtStart];
      [weakSelf.remoteConfigService loadRemoteConfigList:contextKeys includeEmptyContextKey:includeEmptyContextKey completion:completionWrapper];
    }];
  }];
}

- (void)obtainRemoteConfigList:(QONRemoteConfigListCompletionHandler)completion {
  if (![self isOnStateQueue]) {
    [self performStateSync:^{
      [self obtainRemoteConfigList:completion];
    }];
    return;
  }

  NSUInteger userChangeFailureGenerationAtStart = self.userChangeFailureGeneration;

  if (![self.productCenterManager isUserStable]) {
    if ([self failRemoteConfigListRequestWithLastUserChangeError:completion]) {
      return;
    }
    [self enqueueRemoteConfigListRequestWithContextKeys:nil
                                 includeEmptyContextKey:YES
                                             completion:completion];
    return;
  }
  
  __block __weak QONRemoteConfigManager *weakSelf = self;
  QONRemoteConfigCacheScope *scopeAtStart = [self currentRemoteConfigCacheScope];
  NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *stateMapAtStart = self.loadingStates;
  
  [self.userPropertiesManager forceSendProperties:^{
    [weakSelf performStateSync:^{
      if ([weakSelf failRemoteConfigListRequestIfUserChangeFailedSince:userChangeFailureGenerationAtStart completion:completion]) {
        return;
      }
      QONRemoteConfigCacheScope *currentScope = [weakSelf currentRemoteConfigCacheScope];
      if (![weakSelf.productCenterManager isUserStable]) {
        [weakSelf enqueueRemoteConfigListRequestWithContextKeys:nil
                                         includeEmptyContextKey:YES
                                                     completion:completion];
        return;
      }
      if (![weakSelf cacheScope:scopeAtStart equalsScope:currentScope] || stateMapAtStart != weakSelf.loadingStates) {
        [weakSelf obtainRemoteConfigList:completion];
        return;
      }
      QONRemoteConfigListCompletionHandler completionWrapper = [weakSelf remoteConfigListCompletionWrapper:completion contextKeys:nil includeEmptyContextKey:YES scope:scopeAtStart];
      [weakSelf.remoteConfigService loadRemoteConfigList:completionWrapper];
    }];
  }];
}

- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion {
  [self performStateSync:^{
    [self invalidateLoadedConfigs];
  }];
  [self.remoteConfigService attachUserToExperiment:experimentId groupId:groupId completion:completion];
}

- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion {
  [self performStateSync:^{
    [self invalidateLoadedConfigs];
  }];
  [self.remoteConfigService detachUserFromExperiment:experimentId completion:completion];
}

- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [self performStateSync:^{
    [self invalidateLoadedConfigs];
  }];
  [self.remoteConfigService attachUserToRemoteConfiguration:remoteConfigurationId completion:completion];
}

- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion {
  [self performStateSync:^{
    [self invalidateLoadedConfigs];
  }];
  [self.remoteConfigService detachUserFromRemoteConfiguration:remoteConfigurationId completion:completion];
}

// An attach/detach is addressed by experiment/configuration id, and the SDK
// does not know which context key that entity serves — drop every cached
// config, not just the empty-key one, or configs under named context keys stay
// stale until the process restarts. Loading states themselves are kept so
// pending completions survive. The generation bump also stops in-flight loads
// from re-caching a pre-attach response.
- (void)invalidateLoadedConfigs {
  [self bumpCacheGeneration];
  for (QONRemoteConfigLoadingState *loadingState in self.loadingStates.allValues) {
    loadingState.loadedConfig = nil;
  }
}

- (void)executeRemoteConfigCompletionsWithContextKey:(NSString *)contextKey remoteConfig:(QONRemoteConfig *)remoteConfig error:(NSError *)error {
  QONRemoteConfigLoadingState *loadingState = [self loadingStateForContextKey:contextKey];
  if (loadingState) {
    NSArray *completions = [loadingState.completions copy];
    [loadingState.completions removeAllObjects];
    
    for (QONRemoteConfigCompletionHandler completion in completions) {
      [self deferUserCallback:^{
        completion(remoteConfig, error);
      }];
    }
  }
}

- (QONRemoteConfigLoadingState *)loadingStateForContextKey:(NSString *)contextKey {
  NSString *key = contextKey ?: kEmptyContextKey;
  return self.loadingStates[key];
}

- (NSArray<QONRemoteConfig *> *)mergedFallbackConfigsForContextKeys:(NSArray<NSString *> *)contextKeys
                                              includeEmptyContextKey:(BOOL)includeEmptyContextKey
                                                         diskConfigs:(NSArray<QONRemoteConfig *> *)diskConfigs
                                                  bundleConfigList:(QONRemoteConfigList *)bundleConfigList {
  NSArray<QONRemoteConfig *> *bundleConfigs = bundleConfigList.remoteConfigs ?: @[];
  NSMutableDictionary<NSString *, QONRemoteConfig *> *diskByKey = [NSMutableDictionary new];
  NSMutableDictionary<NSString *, QONRemoteConfig *> *bundleByKey = [NSMutableDictionary new];
  for (QONRemoteConfig *config in diskConfigs) {
    diskByKey[[self normalizedContextKey:config.source.contextKey]] = config;
  }
  for (QONRemoteConfig *config in bundleConfigs) {
    bundleByKey[[self normalizedContextKey:config.source.contextKey]] = config;
  }

  NSMutableArray<QONRemoteConfig *> *merged = [NSMutableArray new];
  if (contextKeys) {
    NSMutableArray<NSString *> *requestedKeys = [NSMutableArray new];
    NSMutableSet<NSString *> *seenKeys = [NSMutableSet new];
    for (NSString *contextKey in contextKeys) {
      NSString *normalizedKey = [self normalizedContextKey:contextKey];
      if (![seenKeys containsObject:normalizedKey]) {
        [seenKeys addObject:normalizedKey];
        [requestedKeys addObject:normalizedKey];
      }
    }
    if (includeEmptyContextKey && ![seenKeys containsObject:kEmptyContextKey]) {
      [requestedKeys addObject:kEmptyContextKey];
    }

    // Resolve independently per requested key. A partial disk snapshot must
    // not hide bundled defaults for keys the device has never fetched.
    for (NSString *contextKey in requestedKeys) {
      QONRemoteConfig *config = diskByKey[contextKey] ?: bundleByKey[contextKey];
      if (config) {
        [merged addObject:config];
      }
    }
    return merged;
  }

  // The unfiltered list has no caller-provided ordering. Preserve disk LRU
  // order, then fill only missing context keys from the bundled snapshot.
  NSMutableSet<NSString *> *includedKeys = [NSMutableSet new];
  for (QONRemoteConfig *config in diskConfigs) {
    NSString *contextKey = [self normalizedContextKey:config.source.contextKey];
    if (![includedKeys containsObject:contextKey]) {
      [includedKeys addObject:contextKey];
      [merged addObject:config];
    }
  }
  for (QONRemoteConfig *config in bundleConfigs) {
    NSString *contextKey = [self normalizedContextKey:config.source.contextKey];
    if (![includedKeys containsObject:contextKey]) {
      [includedKeys addObject:contextKey];
      [merged addObject:config];
    }
  }
  return merged;
}

- (QONRemoteConfigListCompletionHandler)remoteConfigListCompletionWrapper:(QONRemoteConfigListCompletionHandler)completion
                                                               contextKeys:(NSArray *)contextKeys
                                                    includeEmptyContextKey:(BOOL)includeEmptyContextKey
                                                                    scope:(QONRemoteConfigCacheScope *)scopeAtStart {
  NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *localLoadingStates = self.loadingStates;
  NSUInteger generationAtStart = self.cacheGeneration;
  NSUInteger userChangeFailureGenerationAtStart = self.userChangeFailureGeneration;

  __block __weak QONRemoteConfigManager *weakSelf = self;

  return ^(QONRemoteConfigList * _Nullable remoteConfigList, NSError * _Nullable error) {
    [weakSelf performStateSync:^{
      if ([weakSelf failRemoteConfigListRequestIfUserChangeFailedSince:userChangeFailureGenerationAtStart completion:completion]) {
        return;
      }
      if (![weakSelf.productCenterManager isUserStable]) {
        [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                         includeEmptyContextKey:includeEmptyContextKey
                                                     completion:completion];
        return;
      }
      QONRemoteConfigCacheScope *currentScope = [weakSelf currentRemoteConfigCacheScope];
      BOOL scopeChanged = ![weakSelf cacheScope:scopeAtStart equalsScope:currentScope];
      BOOL stateMapOrphaned = localLoadingStates != weakSelf.loadingStates;
      if (scopeChanged || stateMapOrphaned) {
        if (contextKeys) {
          [weakSelf obtainRemoteConfigListWithContextKeys:contextKeys
                                  includeEmptyContextKey:includeEmptyContextKey
                                              completion:completion];
        } else {
          [weakSelf obtainRemoteConfigList:completion];
        }
        return;
      }
      if (![weakSelf.productCenterManager isUserStable]) {
        [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                         includeEmptyContextKey:includeEmptyContextKey
                                                     completion:completion];
        return;
      }

      if (error) {
        if (error.shouldFireFallback) {
          NSArray<QONRemoteConfig *> *diskConfigs = [weakSelf persistentLKGForContextKeys:contextKeys
                                                                  includeEmptyContextKey:includeEmptyContextKey
                                                                                   scope:scopeAtStart];
          [weakSelf actualizeFallbackData];
          NSArray<QONRemoteConfig *> *mergedConfigs = [weakSelf mergedFallbackConfigsForContextKeys:contextKeys
                                                                             includeEmptyContextKey:includeEmptyContextKey
                                                                                        diskConfigs:diskConfigs
                                                                                 bundleConfigList:weakSelf.fallbackData.remoteConfigList];
          if (mergedConfigs.count > 0) {
            // A disk/bundle fallback is not a fresh targeting evaluation.
            // Deliver it without warming memory so the next call retries the
            // network instead of pinning the fallback until invalidation.
            BOOL usedDiskLKG = diskConfigs.count > 0;
            if (![weakSelf.productCenterManager isUserStable]) {
              [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                               includeEmptyContextKey:includeEmptyContextKey
                                                           completion:completion];
              return;
            }
            weakSelf.lastDeliveryOrigin = usedDiskLKG
                ? QONRemoteConfigDeliveryOriginDiskLastKnownGood
                : QONRemoteConfigDeliveryOriginBundle;
            QONVERSION_LOG(@"⚠️ Serving %@ remote config list after a transient refresh failure (%@)", usedDiskLKG ? @"disk/bundle last-known-good" : @"bundled fallback", error.localizedDescription);
            QONRemoteConfigList *fallbackList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:mergedConfigs];
            [weakSelf deferUserCallback:^{
              completion(fallbackList, nil);
            }];
            return;
          }
        }
        if (![weakSelf.productCenterManager isUserStable]) {
          [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                           includeEmptyContextKey:includeEmptyContextKey
                                                       completion:completion];
          return;
        }
        [weakSelf deferUserCallback:^{
          completion(nil, error);
        }];
        return;
      }

      if (![weakSelf.productCenterManager isUserStable]) {
        [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                         includeEmptyContextKey:includeEmptyContextKey
                                                     completion:completion];
        return;
      }
      weakSelf.lastDeliveryOrigin = QONRemoteConfigDeliveryOriginServer;
      if (remoteConfigList && generationAtStart == weakSelf.cacheGeneration) {
        // Cache only when no invalidation happened while the list load was in
        // flight — pre-attach evaluations must not be re-cached as fresh. The
        // list is still delivered below either way.
        [weakSelf replacePersistentLKGWithServerList:remoteConfigList
                                        contextKeys:contextKeys
                             includeEmptyContextKey:includeEmptyContextKey
                                              scope:scopeAtStart];
        for (QONRemoteConfig *remoteConfig in remoteConfigList.remoteConfigs) {
          NSString *contextKey = remoteConfig.source.contextKey ?: kEmptyContextKey;
          QONRemoteConfigLoadingState *loadingState = localLoadingStates[contextKey] ?: [QONRemoteConfigLoadingState new];
          loadingState.loadedConfig = remoteConfig;
          localLoadingStates[contextKey] = loadingState;
        }
      }

      if (![weakSelf.productCenterManager isUserStable]) {
        [weakSelf enqueueRemoteConfigListRequestWithContextKeys:contextKeys
                                         includeEmptyContextKey:includeEmptyContextKey
                                                     completion:completion];
        return;
      }
      [weakSelf deferUserCallback:^{
        completion(remoteConfigList, nil);
      }];
    }];
  };
}

- (NSArray<QONRemoteConfig *> *_Nullable)remoteConfigsForContextKeys:(NSArray *)contextKeys remoteConfigList:(QONRemoteConfigList *)remoteConfigList includeEmptyContextKey:(BOOL)includeEmptyContextKey {
  if (contextKeys.count == 0 && !includeEmptyContextKey) {
    return @[];
  }
  
  NSMutableArray *remoteConfigs = [NSMutableArray new];
  for (QONRemoteConfig *remoteConfig in remoteConfigList.remoteConfigs) {
    BOOL shouldAddCurrentRemoteConfigWithEmptyContextKey = includeEmptyContextKey && remoteConfig.source.contextKey.length == 0;
    if (shouldAddCurrentRemoteConfigWithEmptyContextKey || [contextKeys containsObject:remoteConfig.source.contextKey]) {
      [remoteConfigs addObject:remoteConfig];
    }
  }
  
  return [remoteConfigs copy];
}

- (void)actualizeFallbackData {
  self.fallbackData = self.fallbackData ?: [self.fallbackService obtainFallbackData];
}

@end
