//
//  QONRemoteConfigManagerInvalidationTests.m
//  QonversionTests
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QONRemoteConfigManager.h"
#import "QONRemoteConfigService.h"
#import "QONRemoteConfigLoadingState.h"
#import "QONRemoteConfigListRequestData.h"
#import "QNProductCenterManager.h"
#import "QNUserPropertiesManager.h"
#import "QONRemoteConfig.h"
#import "QONRemoteConfig+Protected.h"
#import "QONRemoteConfigList+Protected.h"
#import "QONRemoteConfigMapper.h"
#import "QONRemoteConfigurationSource.h"
#import "QONRemoteConfigurationSource+Protected.h"
#import "QONExperiment+Protected.h"
#import "QONExperimentGroup+Protected.h"
#import "QONFallbackService.h"
#import "QONFallbackObject.h"
#import "QONErrors.h"
#import "Qonversion.h"
#import "QNAPIClient.h"
#import "QNInMemoryStorage.h"
#import "QNLocalStorage.h"
#import "NSError+Sugare.h"

static NSString *const kTestRemoteConfigLKGStorageKey = @"com.qonversion.keys.remote-config-lkg";

static QONRemoteConfig *QONTestRemoteConfig(NSString *identifier, NSString *contextKey, NSString *value) {
  QONRemoteConfigurationSource *source = [[QONRemoteConfigurationSource alloc]
      initWithIdentifier:identifier
                    name:identifier
                    type:QONRemoteConfigurationSourceTypeRemoteConfiguration
          assignmentType:QONRemoteConfigurationAssignmentTypeAuto
              contextKey:contextKey];
  return [[QONRemoteConfig alloc] initWithPayload:@{@"value": value}
                                      experiment:nil
                                          source:source];
}

static QONRemoteConfig *QONTestFrozenExperimentRemoteConfig(NSString *identifier, NSString *contextKey) {
  QONExperimentGroup *group = [[QONExperimentGroup alloc]
      initWithIdentifier:@"group"
                    type:QONExperimentGroupTypeControl
                    name:@"group"];
  QONExperiment *experiment = [[QONExperiment alloc]
      initWithIdentifier:@"experiment"
                    name:@"experiment"
                   group:group];
  QONRemoteConfigurationSource *source = [[QONRemoteConfigurationSource alloc]
      initWithIdentifier:identifier
                    name:identifier
                    type:QONRemoteConfigurationSourceTypeExperimentControlGroup
          assignmentType:QONRemoteConfigurationAssignmentTypeFrozen
              contextKey:contextKey];
  return [[QONRemoteConfig alloc] initWithPayload:@{ @"value": @"frozen" }
                                      experiment:experiment
                                          source:source];
}

static NSDictionary *QONTestRemoteConfigResponse(NSString *identifier, NSString *contextKey) {
  NSMutableDictionary *source = [@{
    @"uid": identifier,
    @"name": identifier,
    @"type": @"remote_configuration",
    @"assignment_type": @"auto",
  } mutableCopy];
  if (contextKey) {
    source[@"context_key"] = contextKey;
  }
  return @{ @"payload": @{ @"value": identifier }, @"source": source };
}

@interface QONThrowingLocalStorage : NSObject <QNLocalStorage>

@property (nonatomic, assign) BOOL removed;

@end


@implementation QONThrowingLocalStorage

- (void)storeObject:(id)object forKey:(NSString *)key {}

- (id)loadObjectForKey:(NSString *)key {
  [NSException raise:NSInvalidUnarchiveOperationException format:@"corrupt archive"];
  return nil;
}

- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion([self loadObjectForKey:key]);
}

- (void)removeObjectForKey:(NSString *)key {
  self.removed = YES;
}

@end

/*
 * Contract tests for the cache invalidation seams (DEV-1231 + DEV-1236 B4).
 *
 * An attach/detach is addressed by experiment/configuration id, and the SDK
 * cannot know which context key that entity serves — so EVERY cached config
 * must be dropped (named keys included) and loading states must survive with
 * their pending completions. The public invalidateRemoteConfigsCache shares
 * the same semantics. A superseded in-flight load (generation moved while the
 * request was flying) is re-issued once per generation instead of delivering
 * the stale evaluation, and bundled fallback configs are delivered without
 * being cached.
 */

@interface QONRemoteConfigManager (InvalidationContractPrivate)

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *loadingStates;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigListRequestData *> *listRequests;
@property (atomic, assign) NSUInteger cacheGeneration;
- (QONRemoteConfigLoadingState *)loadingStateForContextKey:(NSString *)contextKey;
- (BOOL)isOnStateQueue;
- (void)userHasBeenChangedToUserID:(NSString *)userID;
- (void)storePersistentLKGEntries:(NSArray<NSDictionary *> *)entries;
- (NSData *)serializedJSONDataForObject:(id)object;

@end

@interface QONRemoteConfigManagerRaceHarness : QONRemoteConfigManager

@property (atomic, copy) dispatch_block_t loadingStateReadHook;

@end


@implementation QONRemoteConfigManagerRaceHarness

- (QONRemoteConfigLoadingState *)loadingStateForContextKey:(NSString *)contextKey {
  QONRemoteConfigLoadingState *state = [super loadingStateForContextKey:contextKey];
  dispatch_block_t hook = self.loadingStateReadHook;
  if (hook) {
    hook();
  }
  return state;
}

@end

@interface QONRemoteConfigManagerSerializationHarness : QONRemoteConfigManager

@property (nonatomic, assign) NSUInteger serializationCount;

@end


@implementation QONRemoteConfigManagerSerializationHarness

- (NSData *)serializedJSONDataForObject:(id)object {
  self.serializationCount += 1;
  return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

@end

@interface QONRemoteConfigManagerInvalidationTests : XCTestCase

@property (nonatomic, strong) id mockService;
@property (nonatomic, strong) id mockProductCenterManager;
@property (nonatomic, strong) id mockUserPropertiesManager;
@property (nonatomic, strong) id mockFallbackService;
@property (nonatomic, strong) QONRemoteConfigManager *manager;

@end

@implementation QONRemoteConfigManagerInvalidationTests

- (void)setUp {
  [super setUp];

  self.manager = [QONRemoteConfigManager new];

  self.mockService = OCMClassMock([QONRemoteConfigService class]);
  self.mockProductCenterManager = OCMClassMock([QNProductCenterManager class]);
  self.mockUserPropertiesManager = OCMClassMock([QNUserPropertiesManager class]);
  self.mockFallbackService = OCMClassMock([QONFallbackService class]);

  self.manager.remoteConfigService = self.mockService;
  self.manager.productCenterManager = self.mockProductCenterManager;
  self.manager.userPropertiesManager = self.mockUserPropertiesManager;
  self.manager.fallbackService = self.mockFallbackService;
}

- (void)tearDown {
  [self.mockService stopMocking];
  [self.mockProductCenterManager stopMocking];
  [self.mockUserPropertiesManager stopMocking];
  [self.mockFallbackService stopMocking];
  self.manager = nil;

  [super tearDown];
}

- (void)stubUserStableAndImmediatePropertiesFlush {
  OCMStub([self.mockProductCenterManager isUserStable]).andReturn(YES);
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler flushCompletion = nil;
    [invocation getArgument:&flushCompletion atIndex:2];
    if (flushCompletion) {
      flushCompletion();
    }
  });
}

- (void)usePersistentManagerWithStorage:(id<QNLocalStorage>)storage
                              apiClient:(QNAPIClient *)apiClient
               immediatePropertiesFlush:(BOOL)immediatePropertiesFlush {
  self.manager = [[QONRemoteConfigManager alloc] initWithLocalStorage:storage];
  self.manager.remoteConfigService = self.mockService;
  self.manager.productCenterManager = self.mockProductCenterManager;
  self.manager.userPropertiesManager = self.mockUserPropertiesManager;
  self.manager.fallbackService = self.mockFallbackService;
  OCMStub([self.mockService apiClient]).andReturn(apiClient);
  // An unstubbed class mock already returns nil. Do not install a default
  // fallback stub here: OCMock resolves the first matching stub, so a later
  // scenario-specific bundled fallback would otherwise be shadowed.
  if (immediatePropertiesFlush) {
    [self stubUserStableAndImmediatePropertiesFlush];
  }
}

- (void)usePersistentManagerWithStorage:(id<QNLocalStorage>)storage apiClient:(QNAPIClient *)apiClient {
  [self usePersistentManagerWithStorage:storage apiClient:apiClient immediatePropertiesFlush:YES];
}

- (void)seedCachedConfigs {
  QONRemoteConfigLoadingState *emptyKeyState = [QONRemoteConfigLoadingState new];
  emptyKeyState.loadedConfig = OCMClassMock([QONRemoteConfig class]);

  QONRemoteConfigLoadingState *namedKeyState = [QONRemoteConfigLoadingState new];
  namedKeyState.loadedConfig = OCMClassMock([QONRemoteConfig class]);
  [namedKeyState.completions addObject:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];

  self.manager.loadingStates[@""] = emptyKeyState;
  self.manager.loadingStates[@"ctx"] = namedKeyState;
}

- (void)assertInvalidatedForEntryPoint:(NSString *)entryPoint {
  XCTAssertNil(self.manager.loadingStates[@""].loadedConfig,
               @"%@ must drop the empty-key config", entryPoint);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig,
               @"%@ must drop the named-key config", entryPoint);
  XCTAssertNotNil(self.manager.loadingStates[@"ctx"],
                  @"%@ must preserve the loading state", entryPoint);
  XCTAssertEqual(self.manager.loadingStates[@"ctx"].completions.count, 1,
                 @"%@ must preserve pending completions", entryPoint);
}

- (void)testEveryInvalidationEntryPointInvalidatesNamedKeyCachedConfigs {
  // attach to remote configuration
  [self seedCachedConfigs];
  [self.manager attachUserToRemoteConfiguration:@"config_id"
                                     completion:^(BOOL success, NSError * _Nullable error) {}];
  [self assertInvalidatedForEntryPoint:@"attachUserToRemoteConfiguration"];

  // detach from remote configuration
  [self seedCachedConfigs];
  [self.manager detachUserFromRemoteConfiguration:@"config_id"
                                       completion:^(BOOL success, NSError * _Nullable error) {}];
  [self assertInvalidatedForEntryPoint:@"detachUserFromRemoteConfiguration"];

  // attach to experiment
  [self seedCachedConfigs];
  [self.manager attachUserToExperiment:@"experiment_id"
                               groupId:@"group_id"
                            completion:^(BOOL success, NSError * _Nullable error) {}];
  [self assertInvalidatedForEntryPoint:@"attachUserToExperiment"];

  // detach from experiment
  [self seedCachedConfigs];
  [self.manager detachUserFromExperiment:@"experiment_id"
                              completion:^(BOOL success, NSError * _Nullable error) {}];
  [self assertInvalidatedForEntryPoint:@"detachUserFromExperiment"];

  // public cache invalidation (DEV-1236 B4: the same-uid identify path and
  // the public API both route here)
  [self seedCachedConfigs];
  [self.manager invalidateRemoteConfigsCache];
  [self assertInvalidatedForEntryPoint:@"invalidateRemoteConfigsCache"];
}

- (void)testInvalidateMidFlightReissuesLoadAndDeliversFreshEvaluation {
  // given - the user is stable and a single-key load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];

  __block NSUInteger serviceCallCount = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    serviceCallCount += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block NSUInteger deliveryCount = 0;
  __block QONRemoteConfig *deliveredConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveryCount += 1;
    deliveredConfig = remoteConfig;
  }];
  XCTAssertEqual(serviceCallCount, 1, @"the load must reach the service");

  // when - the cache is invalidated mid-flight, then the superseded response
  // lands
  [self.manager invalidateRemoteConfigsCache];
  QONRemoteConfig *staleConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigCompletionHandler firstServiceCompletion = serviceCompletion;
  firstServiceCompletion(staleConfig, nil);

  // then - the stale evaluation is neither delivered nor cached; the load is
  // re-issued exactly once for the awaiting completion
  XCTAssertEqual(deliveryCount, 0);
  XCTAssertEqual(serviceCallCount, 2);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);

  // and the fresh response is delivered, cached, and the state settled
  QONRemoteConfig *freshConfig = OCMClassMock([QONRemoteConfig class]);
  serviceCompletion(freshConfig, nil);
  XCTAssertEqual(deliveryCount, 1);
  XCTAssertEqual(deliveredConfig, freshConfig);
  XCTAssertEqual(self.manager.loadingStates[@"ctx"].loadedConfig, freshConfig);
  XCTAssertFalse(self.manager.loadingStates[@"ctx"].isInProgress);
  XCTAssertEqual(serviceCallCount, 2, @"no runaway retries after the fresh delivery");
}

- (void)testAttachInvalidationMidFlightAlsoReissuesLoad {
  // given - attach shares the invalidation seam with the public API
  [self stubUserStableAndImmediatePropertiesFlush];

  __block NSUInteger serviceCallCount = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    serviceCallCount += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block NSUInteger deliveryCount = 0;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveryCount += 1;
  }];
  XCTAssertEqual(serviceCallCount, 1);

  // when - the attach invalidates mid-flight, then the pre-attach response
  // lands
  [self.manager attachUserToRemoteConfiguration:@"config_id"
                                     completion:^(BOOL success, NSError * _Nullable error) {}];
  serviceCompletion(OCMClassMock([QONRemoteConfig class]), nil);

  // then - the pre-attach evaluation is dropped and the load re-issued
  XCTAssertEqual(deliveryCount, 0);
  XCTAssertEqual(serviceCallCount, 2);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
}

- (void)testCacheHitDrainsQueuedCompletions {
  // given - a warm state that still carries a queued completion (e.g. a list
  // load cached into a state whose own load never fired it, or a completion
  // queued while the user was unstable meets a warm cache on replay)
  [self stubUserStableAndImmediatePropertiesFlush];
  QONRemoteConfig *cachedConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigLoadingState *state = [QONRemoteConfigLoadingState new];
  state.loadedConfig = cachedConfig;
  __block QONRemoteConfig *queuedDelivered = nil;
  [state.completions addObject:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    queuedDelivered = remoteConfig;
  }];
  self.manager.loadingStates[@"ctx"] = state;

  // when - a direct caller hits the warm cache
  __block QONRemoteConfig *directDelivered = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    directDelivered = remoteConfig;
  }];

  // then - both the direct caller and the stranded waiter are served
  XCTAssertEqual(directDelivered, cachedConfig);
  XCTAssertEqual(queuedDelivered, cachedConfig);
  XCTAssertEqual(state.completions.count, 0);
}

- (void)testReissueOntoWarmCacheServesQueuedWaiters {
  // given - a single-key load is in flight with a second caller queued
  [self stubUserStableAndImmediatePropertiesFlush];
  __block NSUInteger singleCalls = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    singleCalls += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  __block QONRemoteConfigListCompletionHandler listServiceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    listServiceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredA = nil;
  __block QONRemoteConfig *deliveredB = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredA = remoteConfig;
  }];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredB = remoteConfig;
  }];
  XCTAssertEqual(singleCalls, 1);

  // when - an invalidation lands, a list load started AFTER it caches the
  // same key, and only then the superseded single-key response arrives, so
  // its re-issue hits the warm cache
  [self.manager invalidateRemoteConfigsCache];
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"]
                               includeEmptyContextKey:NO
                                           completion:^(QONRemoteConfigList * _Nullable remoteConfigList, NSError * _Nullable error) {}];
  QONRemoteConfig *warmConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigurationSource *warmSource = OCMClassMock([QONRemoteConfigurationSource class]);
  OCMStub([warmConfig source]).andReturn(warmSource);
  OCMStub([warmSource contextKey]).andReturn(@"ctx");
  listServiceCompletion([[QONRemoteConfigList alloc] initWithRemoteConfigs:@[warmConfig]], nil);
  serviceCompletion(OCMClassMock([QONRemoteConfig class]), nil);

  // then - BOTH the direct caller and the queued waiter are served with the
  // warm (current generation) config instead of hanging forever, and no
  // second single-key request was needed
  XCTAssertEqual(deliveredA, warmConfig);
  XCTAssertEqual(deliveredB, warmConfig);
  XCTAssertEqual(singleCalls, 1);
  XCTAssertEqual(self.manager.loadingStates[@"ctx"].completions.count, 0);
}

- (void)testFailedReissuePropagatesNonTransientClientError {
  // given - a load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];
  __block NSUInteger singleCalls = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    singleCalls += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  __block NSUInteger deliveryCount = 0;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveryCount += 1;
    deliveredConfig = remoteConfig;
    deliveredError = error;
  }];

  // when - invalidation mid-flight, the superseded (valid) response triggers
  // a re-issue, and the retry returns an authoritative client error
  [self.manager invalidateRemoteConfigsCache];
  QONRemoteConfig *supersededConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigCompletionHandler firstServiceCompletion = serviceCompletion;
  firstServiceCompletion(supersededConfig, nil);
  XCTAssertEqual(singleCalls, 2);
  NSError *clientError = [NSError errorWithDomain:QonversionErrorDomain code:400 userInfo:nil];
  serviceCompletion(nil, clientError);

  // then - a stale baseline must not hide a non-transient response
  XCTAssertEqual(deliveryCount, 1);
  XCTAssertNil(deliveredConfig);
  XCTAssertEqual(deliveredError, clientError);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
}

- (void)testFailedReissuePropagatesAuthorizationError {
  [self stubUserStableAndImmediatePropertiesFlush];
  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredConfig = config;
    deliveredError = error;
  }];
  [self.manager invalidateRemoteConfigsCache];
  serviceCompletions[0](QONTestRemoteConfig(@"superseded", @"ctx", @"old"), nil);
  XCTAssertEqual(serviceCompletions.count, 2);

  NSError *authorizationError = [NSError errorWithDomain:QonversionErrorDomain code:401 userInfo:nil];
  serviceCompletions[1](nil, authorizationError);

  XCTAssertNil(deliveredConfig);
  XCTAssertEqual(deliveredError, authorizationError);
}

- (void)testFailedReissuePrefersBaselineOverBundledFallback {
  // given - a bundled fallback EXISTS for the key, and a load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];
  QONRemoteConfig *bundledConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigurationSource *bundledSource = OCMClassMock([QONRemoteConfigurationSource class]);
  OCMStub([bundledConfig source]).andReturn(bundledSource);
  OCMStub([bundledSource contextKey]).andReturn(@"ctx");
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[bundledConfig]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block NSUInteger singleCalls = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    singleCalls += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredConfig = remoteConfig;
    deliveredError = error;
  }];

  // when - invalidation mid-flight, the superseded response triggers a
  // re-issue, and the retry fails in a FALLBACK-ELIGIBLE way
  [self.manager invalidateRemoteConfigsCache];
  QONRemoteConfig *supersededConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigCompletionHandler firstServiceCompletion = serviceCompletion;
  firstServiceCompletion(supersededConfig, nil);
  XCTAssertEqual(singleCalls, 2);
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorNotConnectedToInternet
                                         userInfo:nil]);

  // then - the real user-specific evaluation seconds old outranks the static
  // bundled payload
  XCTAssertEqual(deliveredConfig, supersededConfig);
  XCTAssertNil(deliveredError);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
}

- (void)testLateJoinerDuringRetryReceivesBaseline {
  // given - a load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredA = nil;
  __block NSError *errorA = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredA = remoteConfig;
    errorA = error;
  }];

  // when - invalidation mid-flight, the superseded response triggers a
  // re-issue, a SECOND caller joins while the retry is flying, and the
  // retry fails transiently
  [self.manager invalidateRemoteConfigsCache];
  QONRemoteConfig *supersededConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigCompletionHandler firstServiceCompletion = serviceCompletion;
  firstServiceCompletion(supersededConfig, nil);
  __block QONRemoteConfig *deliveredB = nil;
  __block NSError *errorB = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredB = remoteConfig;
    errorB = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);

  // then - the never-worse guarantee is uniform: the late joiner gets the
  // baseline too, not the transient retry error
  XCTAssertEqual(deliveredA, supersededConfig);
  XCTAssertEqual(deliveredB, supersededConfig);
  XCTAssertNil(errorA);
  XCTAssertNil(errorB);
}

- (void)testUnstableResponseIgnoredByFailedUserChangeCannotResurfaceLater {
  // given - the superseded response arrives while the user is unstable, so
  // it is ignored and the identity change then fails through the one drain
  // path that bypasses fireRemoteConfig
  __block BOOL userStable = YES;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
  });
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler flushCompletion = nil;
    [invocation getArgument:&flushCompletion atIndex:2];
    if (flushCompletion) {
      flushCompletion();
    }
  });
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredA = nil;
  __block NSError *deliveredErrorA = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredA = remoteConfig;
    deliveredErrorA = error;
  }];
  [self.manager invalidateRemoteConfigsCache];
  userStable = NO;
  QONRemoteConfig *supersededConfig = OCMClassMock([QONRemoteConfig class]);
  serviceCompletion(supersededConfig, nil);
  [self.manager userChangingRequestFailedWithError:[NSError errorWithDomain:@"test" code:1 userInfo:nil]];

  // The response belongs to the identity-stability window and must not cross
  // it. If identify fails, the pending caller receives that failure instead.
  XCTAssertNil(deliveredA);
  XCTAssertNotNil(deliveredErrorA);

  // when - the user stabilises and a later load for the same key fails
  userStable = YES;
  __block QONRemoteConfig *lateConfig = nil;
  __block NSError *lateError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    lateConfig = remoteConfig;
    lateError = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:@"test" code:400 userInfo:nil]);

  // then - the error surfaces; a leftover stash must not deliver a
  // long-superseded evaluation as a success
  XCTAssertNil(lateConfig);
  XCTAssertNotNil(lateError);
}

- (void)testUnstableUserDuringSinglePreflightDefersAllWaitersUntilOneFreshReplay {
  __block BOOL userStable = YES;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
  });
  __block NSMutableArray<QONUserPropertiesEmptyCompletionHandler> *propertyFlushes = [NSMutableArray new];
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:2];
    if (completion) [propertyFlushes addObject:[completion copy]];
  });
  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });

  __block NSUInteger firstDeliveries = 0;
  __block NSUInteger secondDeliveries = 0;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    firstDeliveries += 1;
  }];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    secondDeliveries += 1;
  }];
  XCTAssertEqual(propertyFlushes.count, 1);

  userStable = NO;
  propertyFlushes[0]();
  XCTAssertEqual(serviceCompletions.count, 0, @"an identity-window preflight must not send under the old uid");
  XCTAssertEqual(self.manager.loadingStates[@"ctx"].completions.count, 2);
  XCTAssertFalse(self.manager.loadingStates[@"ctx"].isInProgress);

  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(propertyFlushes.count, 2);
  propertyFlushes[1]();
  XCTAssertEqual(serviceCompletions.count, 1);
  serviceCompletions[0](QONTestRemoteConfig(@"fresh", @"ctx", @"fresh"), nil);
  XCTAssertEqual(firstDeliveries, 1);
  XCTAssertEqual(secondDeliveries, 1);
}

- (void)testUnstableUserAtSingleResponseDoesNotDeliverOldResponseAndReplaysOnce {
  __block BOOL userStable = YES;
  __block BOOL destabilizeAfterNextCheck = NO;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
    if (destabilizeAfterNextCheck) {
      destabilizeAfterNextCheck = NO;
      userStable = NO;
    }
  });
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:2];
    if (completion) completion();
  });
  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });

  __block NSUInteger firstDeliveries = 0;
  __block NSUInteger secondDeliveries = 0;
  __block QONRemoteConfig *deliveredConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    firstDeliveries += 1;
    deliveredConfig = config;
  }];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    secondDeliveries += 1;
  }];
  XCTAssertEqual(serviceCompletions.count, 1);

  destabilizeAfterNextCheck = YES;
  serviceCompletions[0](QONTestRemoteConfig(@"old", @"ctx", @"old"), nil);
  XCTAssertEqual(firstDeliveries, 0);
  XCTAssertEqual(secondDeliveries, 0);
  XCTAssertEqual(self.manager.loadingStates[@"ctx"].completions.count, 2);
  XCTAssertFalse(self.manager.loadingStates[@"ctx"].isInProgress);

  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(serviceCompletions.count, 2, @"all live waiters must share one replay");
  QONRemoteConfig *freshConfig = QONTestRemoteConfig(@"fresh", @"ctx", @"fresh");
  serviceCompletions[1](freshConfig, nil);
  XCTAssertEqual(firstDeliveries, 1);
  XCTAssertEqual(secondDeliveries, 1);
  XCTAssertEqual(deliveredConfig, freshConfig);
}

- (void)testUnstableUserDuringKeyedListPreflightMovesCompletionOnceUntilPendingReplay {
  __block BOOL userStable = YES;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
  });
  __block NSMutableArray<QONUserPropertiesEmptyCompletionHandler> *propertyFlushes = [NSMutableArray new];
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:2];
    if (completion) [propertyFlushes addObject:[completion copy]];
  });
  __block NSMutableArray<QONRemoteConfigListCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    [serviceCompletions addObject:[completion copy]];
  });

  __block NSUInteger deliveries = 0;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveries += 1;
  }];
  XCTAssertEqual(propertyFlushes.count, 1);
  userStable = NO;
  propertyFlushes[0]();
  XCTAssertEqual(serviceCompletions.count, 0);
  XCTAssertEqual(self.manager.listRequests.count, 1);

  [self.manager handlePendingRequests];
  XCTAssertEqual(self.manager.listRequests.count, 1, @"unstable replay must not duplicate the queued completion");
  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(propertyFlushes.count, 2);
  propertyFlushes[1]();
  XCTAssertEqual(serviceCompletions.count, 1);
  serviceCompletions[0]([[QONRemoteConfigList alloc] initWithRemoteConfigs:@[QONTestRemoteConfig(@"fresh", @"ctx", @"fresh")]], nil);
  XCTAssertEqual(deliveries, 1);
}

- (void)testUnstableUserAtUnfilteredListResponseMovesCompletionOnceUntilPendingReplay {
  __block BOOL userStable = YES;
  __block BOOL destabilizeAfterNextCheck = NO;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
    if (destabilizeAfterNextCheck) {
      destabilizeAfterNextCheck = NO;
      userStable = NO;
    }
  });
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:2];
    if (completion) completion();
  });
  __block NSMutableArray<QONRemoteConfigListCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:2];
    [serviceCompletions addObject:[completion copy]];
  });

  __block NSUInteger deliveries = 0;
  __block QONRemoteConfigList *deliveredList = nil;
  [self.manager obtainRemoteConfigList:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveries += 1;
    deliveredList = list;
  }];
  XCTAssertEqual(serviceCompletions.count, 1);
  destabilizeAfterNextCheck = YES;
  serviceCompletions[0]([[QONRemoteConfigList alloc] initWithRemoteConfigs:@[QONTestRemoteConfig(@"old", @"ctx", @"old")]], nil);
  XCTAssertEqual(deliveries, 0);
  XCTAssertEqual(self.manager.listRequests.count, 1);

  [self.manager handlePendingRequests];
  XCTAssertEqual(self.manager.listRequests.count, 1);
  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(serviceCompletions.count, 2);
  QONRemoteConfigList *freshList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[QONTestRemoteConfig(@"fresh", @"ctx", @"fresh")]];
  serviceCompletions[1](freshList, nil);
  XCTAssertEqual(deliveries, 1);
  XCTAssertEqual(deliveredList, freshList);
}

- (void)testUnstableUserDoesNotReceiveWarmKeyedListBeforePendingReplay {
  __block BOOL userStable = NO;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
  });
  QONRemoteConfigLoadingState *warmState = [QONRemoteConfigLoadingState new];
  warmState.loadedConfig = QONTestRemoteConfig(@"old", @"ctx", @"old");
  self.manager.loadingStates[@"ctx"] = warmState;

  __block NSUInteger deliveries = 0;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveries += 1;
  }];
  XCTAssertEqual(deliveries, 0);
  XCTAssertEqual(self.manager.listRequests.count, 1);

  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(deliveries, 1);
  XCTAssertEqual(self.manager.listRequests.count, 0);
}

- (void)testSingleWarmCacheBecomingUnstableDuringPropertyFlushStaysLiveUntilReplay {
  __block BOOL userStable = YES;
  __block BOOL destabilizeOnFlush = YES;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
  });
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    if (destabilizeOnFlush) userStable = NO;
  });
  QONRemoteConfigLoadingState *warmState = [QONRemoteConfigLoadingState new];
  warmState.loadedConfig = QONTestRemoteConfig(@"old", @"ctx", @"old");
  self.manager.loadingStates[@"ctx"] = warmState;

  __block NSUInteger deliveries = 0;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveries += 1;
  }];
  XCTAssertEqual(deliveries, 0);
  XCTAssertEqual(warmState.completions.count, 1);

  destabilizeOnFlush = NO;
  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(deliveries, 1);
  XCTAssertEqual(warmState.completions.count, 0);
}

- (void)testListWarmCacheBecomingUnstableDuringPropertyFlushMovesCompletionUntilReplay {
  __block BOOL userStable = YES;
  __block BOOL destabilizeOnFlush = YES;
  OCMStub([self.mockProductCenterManager isUserStable]).andDo(^(NSInvocation *invocation) {
    [invocation setReturnValue:&userStable];
  });
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    if (destabilizeOnFlush) userStable = NO;
  });
  QONRemoteConfigLoadingState *warmState = [QONRemoteConfigLoadingState new];
  warmState.loadedConfig = QONTestRemoteConfig(@"old", @"ctx", @"old");
  self.manager.loadingStates[@"ctx"] = warmState;

  __block NSUInteger deliveries = 0;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveries += 1;
  }];
  XCTAssertEqual(deliveries, 0);
  XCTAssertEqual(self.manager.listRequests.count, 1);

  destabilizeOnFlush = NO;
  userStable = YES;
  [self.manager handlePendingRequests];
  XCTAssertEqual(deliveries, 1);
  XCTAssertEqual(self.manager.listRequests.count, 0);
}

- (void)testUserSwitchMidFlightReissuesWithoutDeliveringOldIdentityConfig {
  // given - a load is in flight for the old identity
  [self stubUserStableAndImmediatePropertiesFlush];
  __block NSUInteger singleCalls = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    singleCalls += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  __block QONRemoteConfig *deliveredConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredConfig = remoteConfig;
  }];
  XCTAssertEqual(singleCalls, 1);

  // when - the user switches (states map replaced), then the old response
  // lands on the now-orphaned state
  [self.manager userHasBeenChanged];
  QONRemoteConfig *oldIdentityConfig = OCMClassMock([QONRemoteConfig class]);
  serviceCompletion(oldIdentityConfig, nil);

  // then - it must never be delivered across the identity boundary; the live
  // direct caller is re-issued exactly once for the new identity instead
  XCTAssertNil(deliveredConfig);
  XCTAssertEqual(singleCalls, 2);

  QONRemoteConfig *newIdentityConfig = OCMClassMock([QONRemoteConfig class]);
  serviceCompletion(newIdentityConfig, nil);
  XCTAssertEqual(deliveredConfig, newIdentityConfig);
  XCTAssertEqual(singleCalls, 2, @"identity recovery must remain bounded");
}

- (void)testOldIdentityErrorDoesNotDrainNewIdentityWaiters {
  [self stubUserStableAndImmediatePropertiesFlush];
  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });

  __block QONRemoteConfig *oldCallerConfig = nil;
  __block QONRemoteConfig *newCallerConfig = nil;
  __block NSUInteger oldCallerDeliveryCount = 0;
  __block NSUInteger newCallerDeliveryCount = 0;
  __block NSUInteger newWaiterDeliveryCount = 0;
  __block QONRemoteConfig *newWaiterConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    oldCallerDeliveryCount += 1;
    oldCallerConfig = config;
  }];
  XCTAssertEqual(serviceCompletions.count, 1);

  [self.manager userHasBeenChanged];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    newCallerDeliveryCount += 1;
    newCallerConfig = config;
  }];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    newWaiterDeliveryCount += 1;
    newWaiterConfig = config;
  }];
  XCTAssertEqual(serviceCompletions.count, 2);

  serviceCompletions[0](nil, [NSError errorWithDomain:NSURLErrorDomain
                                                  code:NSURLErrorNotConnectedToInternet
                                              userInfo:nil]);
  XCTAssertNil(oldCallerConfig);
  XCTAssertNil(newCallerConfig, @"old error must not drain the new loading state");
  XCTAssertEqual(oldCallerDeliveryCount, 0);
  XCTAssertEqual(newCallerDeliveryCount, 0);
  XCTAssertEqual(newWaiterDeliveryCount, 0, @"old error must not drain a waiter queued on the new loading state");
  XCTAssertEqual(serviceCompletions.count, 2, @"old caller joins the one new-identity request");

  QONRemoteConfig *newIdentityConfig = OCMClassMock([QONRemoteConfig class]);
  serviceCompletions[1](newIdentityConfig, nil);
  XCTAssertEqual(oldCallerConfig, newIdentityConfig);
  XCTAssertEqual(newCallerConfig, newIdentityConfig);
  XCTAssertEqual(oldCallerDeliveryCount, 1);
  XCTAssertEqual(newCallerDeliveryCount, 1);
  XCTAssertEqual(newWaiterDeliveryCount, 1);
  XCTAssertEqual(newWaiterConfig, newIdentityConfig);
}

- (void)testIdentityMutationCannotInterleaveBetweenStateCheckAndOldResponseDelivery {
  QONRemoteConfigManagerRaceHarness *raceManager = [QONRemoteConfigManagerRaceHarness new];
  self.manager = raceManager;
  self.manager.remoteConfigService = self.mockService;
  self.manager.productCenterManager = self.mockProductCenterManager;
  self.manager.userPropertiesManager = self.mockUserPropertiesManager;
  self.manager.fallbackService = self.mockFallbackService;
  [self stubUserStableAndImmediatePropertiesFlush];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];

  dispatch_semaphore_t stateCheckReached = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseOldResponse = dispatch_semaphore_create(0);
  dispatch_semaphore_t oldResponseFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t identityMutationStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t identityMutationFinished = dispatch_semaphore_create(0);
  __block BOOL shouldBlock = YES;
  raceManager.loadingStateReadHook = ^{
    if (shouldBlock) {
      shouldBlock = NO;
      dispatch_semaphore_signal(stateCheckReached);
      dispatch_semaphore_wait(releaseOldResponse, DISPATCH_TIME_FOREVER);
    }
  };

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain
                                                code:NSURLErrorNotConnectedToInternet
                                            userInfo:nil]);
    dispatch_semaphore_signal(oldResponseFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(stateCheckReached, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    dispatch_semaphore_signal(identityMutationStarted);
    [self.manager userHasBeenChanged];
    dispatch_semaphore_signal(identityMutationFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(identityMutationStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  XCTAssertTrue(dispatch_semaphore_wait(identityMutationFinished, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC)) != 0,
                @"identity mutation must wait for the old response's atomic state transition");

  dispatch_semaphore_signal(releaseOldResponse);
  XCTAssertEqual(dispatch_semaphore_wait(identityMutationFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  XCTAssertEqual(dispatch_semaphore_wait(oldResponseFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
}

- (void)testAtomicUserTransitionDoesNotExposeNewAPIUserBeforeManagerStateCanTransition {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"old-user";
  QONRemoteConfigManagerRaceHarness *raceManager = [[QONRemoteConfigManagerRaceHarness alloc] initWithLocalStorage:storage];
  self.manager = raceManager;
  self.manager.remoteConfigService = self.mockService;
  self.manager.productCenterManager = self.mockProductCenterManager;
  self.manager.userPropertiesManager = self.mockUserPropertiesManager;
  self.manager.fallbackService = self.mockFallbackService;
  OCMStub([self.mockService apiClient]).andReturn(apiClient);
  [self stubUserStableAndImmediatePropertiesFlush];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];

  dispatch_semaphore_t stateCheckReached = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseOldResponse = dispatch_semaphore_create(0);
  dispatch_semaphore_t oldResponseFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t transitionStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t transitionFinished = dispatch_semaphore_create(0);
  __block BOOL shouldBlock = YES;
  raceManager.loadingStateReadHook = ^{
    if (shouldBlock) {
      shouldBlock = NO;
      dispatch_semaphore_signal(stateCheckReached);
      dispatch_semaphore_wait(releaseOldResponse, DISPATCH_TIME_FOREVER);
    }
  };

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
    dispatch_semaphore_signal(oldResponseFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(stateCheckReached, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    dispatch_semaphore_signal(transitionStarted);
    [self.manager userHasBeenChangedToUserID:@"new-user"];
    dispatch_semaphore_signal(transitionFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(transitionStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  XCTAssertTrue(dispatch_semaphore_wait(transitionFinished, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC)) != 0);
  XCTAssertEqualObjects(apiClient.userID, @"old-user", @"API identity and manager state must change in one serial transition");

  dispatch_semaphore_signal(releaseOldResponse);
  XCTAssertEqual(dispatch_semaphore_wait(transitionFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  XCTAssertEqual(dispatch_semaphore_wait(oldResponseFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  XCTAssertEqualObjects(apiClient.userID, @"new-user");
}

- (void)testUserTransitionMovesPreflightInitiatorAndWaitersExactlyOnce {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"old-user";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient immediatePropertiesFlush:NO];

  OCMStub([self.mockProductCenterManager isUserStable]).andReturn(YES);
  __block NSMutableArray<QONUserPropertiesEmptyCompletionHandler> *propertyFlushes = [NSMutableArray new];
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler flushCompletion = nil;
    [invocation getArgument:&flushCompletion atIndex:2];
    if (flushCompletion) {
      [propertyFlushes addObject:[flushCompletion copy]];
    }
  });

  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });

  __block NSUInteger initiatorDeliveries = 0;
  __block NSUInteger oldWaiterDeliveries = 0;
  __block NSUInteger newWaiterDeliveries = 0;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    initiatorDeliveries += 1;
  }];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    oldWaiterDeliveries += 1;
  }];
  XCTAssertEqual(propertyFlushes.count, 1);
  XCTAssertEqual(serviceCompletions.count, 0);

  [self.manager userHasBeenChangedToUserID:@"new-user"];
  [self.manager handlePendingRequests];
  XCTAssertEqual(propertyFlushes.count, 2, @"transferred waiters must start one new-identity preflight");

  propertyFlushes[0]();
  XCTAssertEqual(serviceCompletions.count, 0, @"orphaned preflight must never start a request under the new API identity");
  propertyFlushes[1]();
  XCTAssertEqual(serviceCompletions.count, 1);

  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    newWaiterDeliveries += 1;
  }];
  QONRemoteConfig *newConfig = QONTestRemoteConfig(@"new", @"ctx", @"new-value");
  serviceCompletions[0](newConfig, nil);
  XCTAssertEqual(initiatorDeliveries, 1);
  XCTAssertEqual(oldWaiterDeliveries, 1);
  XCTAssertEqual(newWaiterDeliveries, 1);
}

- (void)testNetworkAndMemoryCompletionsRunOutsideStateQueueOnCallingCallbackQueue {
  [self stubUserStableAndImmediatePropertiesFlush];
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  static char callbackQueueKey;
  dispatch_queue_t callbackQueue = dispatch_queue_create("io.qonversion.remote-config-test-callback", DISPATCH_QUEUE_SERIAL);
  dispatch_queue_set_specific(callbackQueue, &callbackQueueKey, &callbackQueueKey, NULL);
  __block BOOL networkCompletionUsedCallbackQueue = NO;
  __block BOOL networkCompletionUsedStateQueue = YES;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    networkCompletionUsedCallbackQueue = dispatch_get_specific(&callbackQueueKey) == &callbackQueueKey;
    networkCompletionUsedStateQueue = [self.manager isOnStateQueue];
  }];
  dispatch_sync(callbackQueue, ^{
    serviceCompletion(QONTestRemoteConfig(@"server", @"ctx", @"value"), nil);
  });
  XCTAssertTrue(networkCompletionUsedCallbackQueue);
  XCTAssertFalse(networkCompletionUsedStateQueue);

  NSThread *callingThread = [NSThread currentThread];
  __block NSThread *memoryCompletionThread = nil;
  __block BOOL memoryCompletionUsedStateQueue = YES;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    memoryCompletionThread = [NSThread currentThread];
    memoryCompletionUsedStateQueue = [self.manager isOnStateQueue];
  }];
  XCTAssertEqual(memoryCompletionThread, callingThread);
  XCTAssertFalse(memoryCompletionUsedStateQueue);
}

- (void)testRateLimitedLoadDeliversBundledFallback {
  // given - a bundled fallback exists and a load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];
  QONRemoteConfig *fallbackConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigurationSource *fallbackSource = OCMClassMock([QONRemoteConfigurationSource class]);
  OCMStub([fallbackConfig source]).andReturn(fallbackSource);
  OCMStub([fallbackSource contextKey]).andReturn(@"ctx");
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[fallbackConfig]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredConfig = remoteConfig;
    deliveredError = error;
  }];
  XCTAssertNotNil(serviceCompletion, @"the load must reach the service");

  // when - the request is short-circuited by the local rate limiter (since
  // fallbacks are no longer cached, offline repeat calls hit the limiter
  // instead of the old cached-fallback fast path)
  // The rate-limit arm of shouldFireFallback is domain-pinned (code 35
  // collides with unrelated domains, e.g. POSIX EAGAIN)
  serviceCompletion(nil, [NSError errorWithDomain:QonversionErrorDomain
                                             code:QONErrorCodeApiRateLimitExceeded
                                         userInfo:nil]);

  // then - the bundled payload is served instead of a hard error, uncached
  XCTAssertEqual(deliveredConfig, fallbackConfig);
  XCTAssertNil(deliveredError);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
}

- (void)testFallbackConfigIsDeliveredWithoutBeingCached {
  // given - a bundled fallback exists and a single-key load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];

  QONRemoteConfig *fallbackConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigurationSource *fallbackSource = OCMClassMock([QONRemoteConfigurationSource class]);
  OCMStub([fallbackConfig source]).andReturn(fallbackSource);
  OCMStub([fallbackSource contextKey]).andReturn(@"ctx");
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[fallbackConfig]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredConfig = remoteConfig;
  }];
  XCTAssertNotNil(serviceCompletion, @"the load must reach the service");

  // when - the network fails in a fallback-eligible way
  NSError *networkError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
  serviceCompletion(nil, networkError);

  // then - the fallback is delivered but NOT pinned into the cache, so the
  // next call retries the network instead of serving the fallback until the
  // next invalidation
  XCTAssertEqual(deliveredConfig, fallbackConfig);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
  XCTAssertFalse(self.manager.loadingStates[@"ctx"].isInProgress);
}

- (void)testFallbackListIsBuiltFromBundledDataAndNotCached {
  // given - a bundled fallback exists and a keyed list load is in flight
  [self stubUserStableAndImmediatePropertiesFlush];

  QONRemoteConfig *fallbackConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigurationSource *fallbackSource = OCMClassMock([QONRemoteConfigurationSource class]);
  OCMStub([fallbackConfig source]).andReturn(fallbackSource);
  OCMStub([fallbackSource contextKey]).andReturn(@"ctx");
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[fallbackConfig]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block QONRemoteConfigListCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfigList *deliveredList = nil;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"]
                               includeEmptyContextKey:NO
                                           completion:^(QONRemoteConfigList * _Nullable remoteConfigList, NSError * _Nullable error) {
    deliveredList = remoteConfigList;
  }];
  XCTAssertNotNil(serviceCompletion, @"the list load must reach the service");

  // when - the network fails in a fallback-eligible way
  NSError *networkError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
  serviceCompletion(nil, networkError);

  // then - the keyed fallback is filtered from the BUNDLED list (previously
  // it was filtered from the nil network list and always came back empty),
  // delivered, and nothing is cached
  XCTAssertEqual(deliveredList.remoteConfigs.count, 1);
  XCTAssertEqual(deliveredList.remoteConfigs.firstObject, fallbackConfig);
  XCTAssertNil(self.manager.loadingStates[@"ctx"]);
}

- (void)testAttachInvalidationPreventsInFlightListLoadFromReCachingStaleConfigs {
  // given - the user is stable and a list load is in flight (attach does NOT
  // replace the states map, so the generation guard is the only barrier here)
  OCMStub([self.mockProductCenterManager isUserStable]).andReturn(YES);
  OCMStub([self.mockUserPropertiesManager forceSendProperties:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONUserPropertiesEmptyCompletionHandler flushCompletion = nil;
    [invocation getArgument:&flushCompletion atIndex:2];
    if (flushCompletion) {
      flushCompletion();
    }
  });

  __block QONRemoteConfigListCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    serviceCompletion = [completion copy];
  });

  __block QONRemoteConfigList *deliveredList = nil;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"]
                               includeEmptyContextKey:NO
                                           completion:^(QONRemoteConfigList * _Nullable remoteConfigList, NSError * _Nullable error) {
    deliveredList = remoteConfigList;
  }];
  XCTAssertNotNil(serviceCompletion, @"the list load must reach the service");

  // when - the attach invalidates mid-flight, then the pre-attach list lands
  [self.manager attachUserToRemoteConfiguration:@"config_id"
                                     completion:^(BOOL success, NSError * _Nullable error) {}];

  // Typed receivers: with plain id the compiler cannot disambiguate the many
  // -source selectors in scope and fails the build.
  QONRemoteConfig *staleConfig = OCMClassMock([QONRemoteConfig class]);
  QONRemoteConfigurationSource *staleSource = OCMClassMock([QONRemoteConfigurationSource class]);
  OCMStub([staleConfig source]).andReturn(staleSource);
  OCMStub([staleSource contextKey]).andReturn(@"ctx");
  QONRemoteConfigList *staleList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[staleConfig]];
  serviceCompletion(staleList, nil);

  // then - the list is delivered but nothing from it is cached
  XCTAssertEqual(deliveredList, staleList);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
}

- (void)testProcessRestartOfflineServesDiskLKGBeforeBundleAndRetriesNetworkOnNextCall {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block NSUInteger serviceCalls = 0;
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    serviceCalls += 1;
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  QONRemoteConfig *serverConfig = QONTestRemoteConfig(@"server", @"ctx", @"server-value");
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(serverConfig, nil);
  XCTAssertNotNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);

  // Simulate a process restart: a new manager has no in-memory loading state,
  // but receives the same durable storage and identity scope.
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  QONRemoteConfig *bundledConfig = QONTestRemoteConfig(@"bundle", @"ctx", @"bundle-value");
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[bundledConfig]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredConfig = config;
    deliveredError = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);

  XCTAssertEqualObjects(deliveredConfig.payload, serverConfig.payload);
  XCTAssertEqualObjects(deliveredConfig.source.identifier, @"server");
  XCTAssertNil(deliveredError);
  XCTAssertEqual(self.manager.lastDeliveryOrigin, QONRemoteConfigDeliveryOriginDiskLastKnownGood);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig,
               @"disk LKG must not become a warm cache that suppresses recovery");

  // A second caller performs one more bounded network attempt and degrades to
  // the same disk value again if the outage persists.
  deliveredConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredConfig = config;
  }];
  XCTAssertEqual(serviceCalls, 3);
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]);
  XCTAssertEqualObjects(deliveredConfig.source.identifier, @"server");
  XCTAssertEqual(serviceCalls, 3);
}

- (void)testSameIdentityInvalidationRetainsDiskLKGButScopeChangesNeverReadIt {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"user-a-config", @"ctx", @"a"), nil);

  [self.manager invalidateRemoteConfigsCache];
  __block QONRemoteConfig *sameIdentityConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    sameIdentityConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertEqualObjects(sameIdentityConfig.source.identifier, @"user-a-config");

  apiClient.userID = @"user-b";
  [self.manager userHasBeenChanged];
  __block QONRemoteConfig *otherUserConfig = nil;
  __block NSError *otherUserError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    otherUserConfig = config;
    otherUserError = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNil(otherUserConfig);
  XCTAssertNotNil(otherUserError);

  apiClient.userID = @"user-a";
  apiClient.apiKey = @"project-b";
  [self.manager userHasBeenChanged];
  __block QONRemoteConfig *otherProjectConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    otherProjectConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNil(otherProjectConfig);

  apiClient.apiKey = @"project-a";
  [self.manager userHasBeenChanged];
  __block QONRemoteConfig *otherContextConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"other-context"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    otherContextConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNil(otherContextConfig);
}

- (void)testInvalidServerValueIsNeverPersistedAsLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  QONRemoteConfig *invalidConfig = [[QONRemoteConfig alloc] initWithPayload:@{@"value": @"invalid"}
                                                                 experiment:nil
                                                                     source:nil];
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(invalidConfig, nil);
  XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);
}

- (void)testAuthoritativeNoConfigResponseRemovesStaleDiskLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"stale", @"ctx", @"stale-value"), nil);
  [self.manager invalidateRemoteConfigsCache];

  __block NSError *notAvailableError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    notAvailableError = error;
  }];
  serviceCompletion(nil, [QONErrors errorWithCode:QONErrorCodeRemoteConfigurationNotAvailable
                                           message:@"not available"]);
  XCTAssertEqual(notAvailableError.code, QONErrorCodeRemoteConfigurationNotAvailable);

  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    XCTAssertNil(config);
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorNotConnectedToInternet
                                         userInfo:nil]);
}

- (void)testAuthoritativeNoConfigRetryDoesNotServeBaselineAndRemovesStaleDiskLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });

  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletions[0](QONTestRemoteConfig(@"persisted", @"ctx", @"persisted"), nil);
  XCTAssertNotNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);

  [self.manager invalidateRemoteConfigsCache];
  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredConfig = config;
    deliveredError = error;
  }];
  [self.manager invalidateRemoteConfigsCache];
  serviceCompletions[1](QONTestRemoteConfig(@"superseded", @"ctx", @"superseded"), nil);
  XCTAssertEqual(serviceCompletions.count, 3);

  NSError *notAvailableError = [QONErrors errorWithCode:QONErrorCodeRemoteConfigurationNotAvailable
                                                message:@"not available"];
  serviceCompletions[2](nil, notAvailableError);

  XCTAssertNil(deliveredConfig);
  XCTAssertEqual(deliveredError, notAvailableError);
  XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);
}

- (void)testUnknownSchemaAndCorruptArchiveAreIgnoredAndCleared {
  QNInMemoryStorage *unknownSchemaStorage = [QNInMemoryStorage new];
  [unknownSchemaStorage storeObject:@{@"schema_version": @99, @"scopes": @{}}
                             forKey:kTestRemoteConfigLKGStorageKey];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:unknownSchemaStorage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredError = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNotNil(deliveredError);
  XCTAssertNil([unknownSchemaStorage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);

  QONThrowingLocalStorage *corruptStorage = [QONThrowingLocalStorage new];
  [self usePersistentManagerWithStorage:corruptStorage apiClient:apiClient];
  deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredError = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNotNil(deliveredError);
  XCTAssertTrue(corruptStorage.removed);
}

- (void)testListPathUsesDiskLKGBeforeBundleAndDoesNotWarmMemoryCache {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler singleCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    singleCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  singleCompletion(QONTestRemoteConfig(@"disk", @"ctx", @"disk-value"), nil);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  QONRemoteConfig *bundledConfig = QONTestRemoteConfig(@"bundle", @"ctx", @"bundle-value");
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[bundledConfig]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block NSUInteger listCalls = 0;
  __block QONRemoteConfigListCompletionHandler listCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    listCalls += 1;
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    listCompletion = [completion copy];
  });

  __block QONRemoteConfigList *deliveredList = nil;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"]
                               includeEmptyContextKey:NO
                                           completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredList = list;
  }];
  listCompletion(nil, [NSError errorWithDomain:QonversionErrorDomain code:503 userInfo:nil]);

  XCTAssertEqual(deliveredList.remoteConfigs.count, 1);
  XCTAssertEqualObjects(deliveredList.remoteConfigs.firstObject.source.identifier, @"disk");
  XCTAssertEqual(self.manager.lastDeliveryOrigin, QONRemoteConfigDeliveryOriginDiskLastKnownGood);
  XCTAssertNil(self.manager.loadingStates[@"ctx"]);

  deliveredList = nil;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"]
                               includeEmptyContextKey:NO
                                           completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredList = list;
  }];
  XCTAssertEqual(listCalls, 2);
  listCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);
  XCTAssertEqualObjects(deliveredList.remoteConfigs.firstObject.source.identifier, @"disk");
}

- (void)testListFallbackMergesEachRequestedKeyWithDiskBeforeBundle {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler singleCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    singleCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"disk-key"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  singleCompletion(QONTestRemoteConfig(@"disk-winner", @"disk-key", @"disk"), nil);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  QONFallbackObject *fallbackObject = [QONFallbackObject new];
  fallbackObject.remoteConfigList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[
    QONTestRemoteConfig(@"bundle-loser", @"disk-key", @"bundle-old"),
    QONTestRemoteConfig(@"bundle-missing-key", @"bundle-key", @"bundle"),
  ]];
  OCMStub([self.mockFallbackService obtainFallbackData]).andReturn(fallbackObject);

  __block QONRemoteConfigListCompletionHandler listCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    listCompletion = [completion copy];
  });

  __block QONRemoteConfigList *deliveredList = nil;
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"disk-key", @"bundle-key"]
                               includeEmptyContextKey:NO
                                           completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredList = list;
  }];
  listCompletion(nil, [NSError errorWithDomain:QonversionErrorDomain code:503 userInfo:nil]);

  XCTAssertEqual(deliveredList.remoteConfigs.count, 2);
  XCTAssertEqualObjects([deliveredList remoteConfigForContextKey:@"disk-key"].source.identifier, @"disk-winner");
  XCTAssertEqualObjects([deliveredList remoteConfigForContextKey:@"bundle-key"].source.identifier, @"bundle-missing-key");
  XCTAssertEqual(self.manager.lastDeliveryOrigin, QONRemoteConfigDeliveryOriginDiskLastKnownGood);
}

- (void)testPersistentCacheIsGloballyBoundedAndEvictsLeastRecentlyUsedEntry {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  for (NSUInteger index = 0; index < 64; index++) {
    NSString *contextKey = [NSString stringWithFormat:@"ctx-%lu", (unsigned long)index];
    [self.manager obtainRemoteConfigWithContextKey:contextKey
                                        completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
    serviceCompletion(QONTestRemoteConfig(contextKey, contextKey, contextKey), nil);
  }

  // Restart and read ctx-0 from disk to make it most-recently-used.
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfig *touchedConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx-0"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    touchedConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertEqualObjects(touchedConfig.source.identifier, @"ctx-0");

  [self.manager obtainRemoteConfigWithContextKey:@"ctx-64"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"ctx-64", @"ctx-64", @"ctx-64"), nil);

  NSDictionary *root = [storage loadObjectForKey:kTestRemoteConfigLKGStorageKey];
  XCTAssertEqual([root[@"entries"] count], 64);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfig *evictedConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx-1"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    evictedConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNil(evictedConfig);

  __block QONRemoteConfig *retainedConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx-0"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    retainedConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertEqualObjects(retainedConfig.source.identifier, @"ctx-0");
}

- (void)testPersistentCacheLargeBatchUsesOnePassByteBudgetAndKeepsNewestSuffix {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigManagerSerializationHarness *manager =
      [[QONRemoteConfigManagerSerializationHarness alloc] initWithLocalStorage:storage];
  NSString *nearLimitValue = [@"x" stringByPaddingToLength:480 * 1024
                                                withString:@"x"
                                           startingAtIndex:0];
  NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
  for (NSUInteger index = 0; index < 64; index++) {
    [entries addObject:@{
      @"project_key": @"project-a",
      @"effective_api_key": @"project-a",
      @"environment": @"production",
      @"user_id": @"user-a",
      @"context_key": [NSString stringWithFormat:@"ctx-%lu", (unsigned long)index],
      @"config": @{
        @"payload": @{ @"value": nearLimitValue },
        @"source": @{
          @"identifier": @"source",
          @"name": @"source",
          @"type": @(QONRemoteConfigurationSourceTypeRemoteConfiguration),
          @"assignment_type": @(QONRemoteConfigurationAssignmentTypeAuto),
          @"context_key": [NSString stringWithFormat:@"ctx-%lu", (unsigned long)index],
        },
        @"experiment": [NSNull null],
      },
    }];
  }

  [manager storePersistentLKGEntries:entries];

  NSDictionary *root = [storage loadObjectForKey:kTestRemoteConfigLKGStorageKey];
  NSArray *storedEntries = root[@"entries"];
  XCTAssertEqual(storedEntries.count, 1);
  XCTAssertEqualObjects(storedEntries.firstObject[@"context_key"], @"ctx-63",
                        @"byte eviction must keep the deterministic newest suffix");
  XCTAssertGreaterThan(manager.serializationCount, 0);
  XCTAssertLessThanOrEqual(manager.serializationCount, 66,
                           @"64 entries require at most one serialization each, plus empty and final roots");
}

- (void)testPersistentCacheRejectsSingleEntryAboveByteQuotaWithoutEvictingValidLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"valid"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"valid", @"valid", @"small"), nil);

  NSString *oversizedValue = [@"x" stringByPaddingToLength:600 * 1024 withString:@"x" startingAtIndex:0];
  [self.manager obtainRemoteConfigWithContextKey:@"oversized"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"oversized", @"oversized", oversizedValue), nil);
  NSDictionary *root = [storage loadObjectForKey:kTestRemoteConfigLKGStorageKey];
  XCTAssertEqual([root[@"entries"] count], 1);
  XCTAssertEqualObjects(root[@"entries"][0][@"context_key"], @"valid");
}

- (void)testPersistentScopeSeparatesProductionAndSandboxEffectiveAPIKeys {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  apiClient.debug = NO;
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"production", @"ctx", @"production"), nil);

  NSDictionary *root = [storage loadObjectForKey:kTestRemoteConfigLKGStorageKey];
  NSDictionary *productionEntry = root[@"entries"][0];
  XCTAssertEqualObjects(productionEntry[@"environment"], @"production");
  XCTAssertEqualObjects(productionEntry[@"effective_api_key"], @"project-a");

  apiClient.debug = YES;
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfig *sandboxConfig = nil;
  __block NSError *sandboxError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    sandboxConfig = config;
    sandboxError = error;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertNil(sandboxConfig, @"sandbox must never receive production LKG for the same raw project key");
  XCTAssertNotNil(sandboxError);
}

- (void)testPersistentLKGAcceptsKnownFrozenAndExperimentEnumValues {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestFrozenExperimentRemoteConfig(@"frozen", @"ctx"), nil);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfig *diskConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    diskConfig = config;
  }];
  serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]);
  XCTAssertEqual(diskConfig.source.assignmentType, QONRemoteConfigurationAssignmentTypeFrozen);
  XCTAssertEqual(diskConfig.source.type, QONRemoteConfigurationSourceTypeExperimentControlGroup);
  XCTAssertEqual(diskConfig.experiment.group.type, QONExperimentGroupTypeControl);
}

- (void)testPersistentLKGRejectsUnknownSemanticEnumValuesAndClearsArchive {
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";

  // Keep one matching OCMock stub for the whole table-driven test. Adding the
  // same stub inside the loop makes OCMock keep invoking the first iteration's
  // block, leaving the current serviceCompletion nil and crashing the test host.
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  NSArray<NSString *> *corruptionKinds = @[@"source", @"assignment", @"group"];
  for (NSString *corruptionKind in corruptionKinds) {
    QNInMemoryStorage *storage = [QNInMemoryStorage new];
    [self usePersistentManagerWithStorage:storage apiClient:apiClient];

    serviceCompletion = nil;
    [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
    XCTAssertNotNil(serviceCompletion);
    if (!serviceCompletion) {
      continue;
    }
    serviceCompletion(QONTestFrozenExperimentRemoteConfig(@"frozen", @"ctx"), nil);

    NSMutableDictionary *root = [[storage loadObjectForKey:kTestRemoteConfigLKGStorageKey] mutableCopy];
    NSMutableArray *entries = [root[@"entries"] mutableCopy];
    NSMutableDictionary *entry = [entries[0] mutableCopy];
    NSMutableDictionary *storedConfig = [entry[@"config"] mutableCopy];
    if ([corruptionKind isEqualToString:@"group"]) {
      NSMutableDictionary *experiment = [storedConfig[@"experiment"] mutableCopy];
      NSMutableDictionary *group = [experiment[@"group"] mutableCopy];
      group[@"type"] = @999;
      experiment[@"group"] = group;
      storedConfig[@"experiment"] = experiment;
    } else {
      NSMutableDictionary *source = [storedConfig[@"source"] mutableCopy];
      source[[corruptionKind isEqualToString:@"source"] ? @"type" : @"assignment_type"] = @999;
      storedConfig[@"source"] = source;
    }
    entry[@"config"] = storedConfig;
    entries[0] = entry;
    root[@"entries"] = entries;
    [storage storeObject:root forKey:kTestRemoteConfigLKGStorageKey];

    [self usePersistentManagerWithStorage:storage apiClient:apiClient];
    __block QONRemoteConfig *deliveredConfig = nil;
    __block NSError *deliveredError = nil;
    serviceCompletion = nil;
    [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
      deliveredConfig = config;
      deliveredError = error;
    }];
    XCTAssertNotNil(serviceCompletion);
    if (!serviceCompletion) {
      continue;
    }
    serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]);
    XCTAssertNil(deliveredConfig, @"unknown %@ enum must never be served from disk", corruptionKind);
    XCTAssertNotNil(deliveredError);
    XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey], @"semantic corruption must clear the archive");
  }
}

- (void)testPersistentLKGRejectsFractionalAndBooleanEnumValuesAndClearsArchive {
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";

  // The callback stub must be shared across iterations for the same reason as
  // the semantic-enum table above: duplicate matching stubs retain stale block
  // storage and turn a normal assertion failure into a test-host crash.
  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });

  NSArray<NSDictionary *> *corruptions = @[
    @{ @"kind": @"source", @"value": @0.5 },
    @{ @"kind": @"assignment", @"value": @YES },
    @{ @"kind": @"group", @"value": @0.5 },
  ];
  for (NSDictionary *corruption in corruptions) {
    QNInMemoryStorage *storage = [QNInMemoryStorage new];
    [self usePersistentManagerWithStorage:storage apiClient:apiClient];

    serviceCompletion = nil;
    [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
    XCTAssertNotNil(serviceCompletion);
    if (!serviceCompletion) {
      continue;
    }
    serviceCompletion(QONTestFrozenExperimentRemoteConfig(@"frozen", @"ctx"), nil);

    NSMutableDictionary *root = [[storage loadObjectForKey:kTestRemoteConfigLKGStorageKey] mutableCopy];
    NSMutableArray *entries = [root[@"entries"] mutableCopy];
    NSMutableDictionary *entry = [entries[0] mutableCopy];
    NSMutableDictionary *storedConfig = [entry[@"config"] mutableCopy];
    NSString *kind = corruption[@"kind"];
    if ([kind isEqualToString:@"group"]) {
      NSMutableDictionary *experiment = [storedConfig[@"experiment"] mutableCopy];
      NSMutableDictionary *group = [experiment[@"group"] mutableCopy];
      group[@"type"] = corruption[@"value"];
      experiment[@"group"] = group;
      storedConfig[@"experiment"] = experiment;
    } else {
      NSMutableDictionary *source = [storedConfig[@"source"] mutableCopy];
      source[[kind isEqualToString:@"source"] ? @"type" : @"assignment_type"] = corruption[@"value"];
      storedConfig[@"source"] = source;
    }
    entry[@"config"] = storedConfig;
    entries[0] = entry;
    root[@"entries"] = entries;
    [storage storeObject:root forKey:kTestRemoteConfigLKGStorageKey];

    [self usePersistentManagerWithStorage:storage apiClient:apiClient];
    __block QONRemoteConfig *deliveredConfig = nil;
    __block NSError *deliveredError = nil;
    serviceCompletion = nil;
    [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
      deliveredConfig = config;
      deliveredError = error;
    }];
    XCTAssertNotNil(serviceCompletion);
    if (!serviceCompletion) {
      continue;
    }
    serviceCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]);

    XCTAssertNil(deliveredConfig, @"non-integral %@ enum must never be served from disk", kind);
    XCTAssertNotNil(deliveredError);
    XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey],
                 @"non-integral semantic corruption must clear the archive");
  }
}

- (void)testSupersededSingleResponseDoesNotReachDiskBeforeFreshGeneration {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block NSMutableArray<QONRemoteConfigCompletionHandler> *serviceCompletions = [NSMutableArray new];
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    [serviceCompletions addObject:[completion copy]];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  [self.manager invalidateRemoteConfigsCache];
  serviceCompletions[0](QONTestRemoteConfig(@"stale", @"ctx", @"stale"), nil);
  XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey], @"superseded generation must not become restart LKG");
  XCTAssertEqual(serviceCompletions.count, 2);

  serviceCompletions[1](QONTestRemoteConfig(@"fresh", @"ctx", @"fresh"), nil);
  XCTAssertNotNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);
}

- (void)testSupersededListResponseDoesNotReachDisk {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigListCompletionHandler listCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    listCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {}];
  [self.manager invalidateRemoteConfigsCache];
  QONRemoteConfigList *staleList = [[QONRemoteConfigList alloc] initWithRemoteConfigs:@[QONTestRemoteConfig(@"stale", @"ctx", @"stale")]];
  listCompletion(staleList, nil);
  XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);
}

- (void)testOversizedServerListEntryKeepsOlderSameKeyLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler singleCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    singleCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  singleCompletion(QONTestRemoteConfig(@"old-valid", @"ctx", @"old"), nil);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfigListCompletionHandler listCompletion = nil;
  OCMStub([self.mockService loadRemoteConfigList:[OCMArg any] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigListCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    listCompletion = [completion copy];
  });
  NSString *oversizedValue = [@"x" stringByPaddingToLength:600 * 1024 withString:@"x" startingAtIndex:0];
  [self.manager obtainRemoteConfigListWithContextKeys:@[@"ctx"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {}];
  listCompletion([[QONRemoteConfigList alloc] initWithRemoteConfigs:@[QONTestRemoteConfig(@"too-large", @"ctx", oversizedValue)]], nil);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfig *fallbackConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    fallbackConfig = config;
  }];
  singleCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
  XCTAssertEqualObjects(fallbackConfig.source.identifier, @"old-valid");
}

- (void)testInternalResponseFailureUsesDiskLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler serviceCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    serviceCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  serviceCompletion(QONTestRemoteConfig(@"disk", @"ctx", @"disk"), nil);

  [self usePersistentManagerWithStorage:storage apiClient:apiClient];
  __block QONRemoteConfig *fallbackConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    fallbackConfig = config;
  }];
  serviceCompletion(nil, [QONErrors internalErrorWithCode:QONErrorCodeResponseParsingFailed]);
  XCTAssertEqualObjects(fallbackConfig.source.identifier, @"disk");
  XCTAssertEqual(self.manager.lastDeliveryOrigin, QONRemoteConfigDeliveryOriginDiskLastKnownGood);
}

- (void)testRemoteConfigServiceMapsNoSourceToNotAvailableAndMalformedSuccessToInternalError {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientDictCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientDictCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    apiCompletion = [completion copy];
  });

  __block NSError *emptyError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    emptyError = error;
  }];
  apiCompletion(@{}, nil);
  XCTAssertEqual(emptyError.code, QONErrorCodeRemoteConfigurationNotAvailable);

  __block NSError *noSourceError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    noSourceError = error;
  }];
  apiCompletion(@{ @"payload": @{} }, nil);
  XCTAssertEqual(noSourceError.code, QONErrorCodeRemoteConfigurationNotAvailable);

  __block NSError *malformedSourceError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    malformedSourceError = error;
  }];
  apiCompletion(@{ @"payload": @{}, @"source": @{} }, nil);
  XCTAssertEqual(malformedSourceError.code, QONErrorCodeInternalError);

  __block NSError *malformedError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    malformedError = error;
  }];
  apiCompletion(@{
    @"payload": @"not-a-dictionary",
    @"source": @{
      @"uid": @"source",
      @"name": @"source",
      @"type": @"remote_configuration",
      @"assignment_type": @"auto",
    },
  }, nil);
  XCTAssertEqual(malformedError.code, QONErrorCodeInternalError);

  __block NSError *invalidContextTypeError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    invalidContextTypeError = error;
  }];
  apiCompletion(@{
    @"payload": @{},
    @"source": @{
      @"uid": @"source",
      @"name": @"source",
      @"type": @"remote_configuration",
      @"assignment_type": @"auto",
      @"context_key": @42,
    },
  }, nil);
  XCTAssertEqual(invalidContextTypeError.code, QONErrorCodeInternalError);

  __block NSError *malformedExperimentError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    malformedExperimentError = error;
  }];
  apiCompletion(@{
    @"payload": @{},
    @"source": @{
      @"uid": @"source",
      @"name": @"source",
      @"type": @"remote_configuration",
      @"assignment_type": @"auto",
    },
    @"experiment": @{
      @"uid": @42,
      @"name": @"experiment",
      @"group": @{
        @"uid": @"group",
        @"name": @"group",
        @"type": @"control",
      },
    },
  }, nil);
  XCTAssertEqual(malformedExperimentError.code, QONErrorCodeInternalError);
  [apiClientMock stopMocking];
}

- (void)testServiceNoConfigResponseRemovesManagerDiskLKGAndSurfacesNotAvailable {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QNAPIClient *apiClient = [QNAPIClient new];
  apiClient.apiKey = @"project-a";
  apiClient.userID = @"user-a";
  [self usePersistentManagerWithStorage:storage apiClient:apiClient];

  __block QONRemoteConfigCompletionHandler seedCompletion = nil;
  OCMStub([self.mockService loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QONRemoteConfigCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    seedCompletion = [completion copy];
  });
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {}];
  seedCompletion(QONTestRemoteConfig(@"stale", @"ctx", @"stale"), nil);
  XCTAssertNotNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);

  id apiClientMock = OCMPartialMock(apiClient);
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  service.apiClient = apiClientMock;
  __block QNAPIClientDictCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfig:@"ctx" completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientDictCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    apiCompletion = [completion copy];
  });

  self.manager = [[QONRemoteConfigManager alloc] initWithLocalStorage:storage];
  self.manager.remoteConfigService = service;
  self.manager.productCenterManager = self.mockProductCenterManager;
  self.manager.userPropertiesManager = self.mockUserPropertiesManager;
  self.manager.fallbackService = self.mockFallbackService;

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredConfig = config;
    deliveredError = error;
  }];
  apiCompletion(@{}, nil);

  XCTAssertNil(deliveredConfig);
  XCTAssertEqual(deliveredError.code, QONErrorCodeRemoteConfigurationNotAvailable);
  XCTAssertNil([storage loadObjectForKey:kTestRemoteConfigLKGStorageKey]);
  [apiClientMock stopMocking];
}

- (void)testRemoteConfigServiceRejectsSingleContextMismatch {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientDictCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfig:@"requested" completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientDictCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    apiCompletion = [completion copy];
  });

  __block QONRemoteConfig *deliveredConfig = nil;
  __block NSError *deliveredError = nil;
  [service loadRemoteConfig:@"requested" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    deliveredConfig = config;
    deliveredError = error;
  }];
  apiCompletion(QONTestRemoteConfigResponse(@"unexpected", @"other"), nil);

  XCTAssertNil(deliveredConfig);
  XCTAssertEqual(deliveredError.code, QONErrorCodeInternalError);
  [apiClientMock stopMocking];
}

- (void)testRemoteConfigServiceRejectsUnexpectedFilteredListContext {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientArrayCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfigListForContextKeys:@[@"requested"] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientArrayCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    apiCompletion = [completion copy];
  });

  __block QONRemoteConfigList *deliveredList = nil;
  __block NSError *deliveredError = nil;
  [service loadRemoteConfigList:@[@"requested"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredList = list;
    deliveredError = error;
  }];
  apiCompletion(@[QONTestRemoteConfigResponse(@"unexpected", @"other")], nil);

  XCTAssertNil(deliveredList);
  XCTAssertEqual(deliveredError.code, QONErrorCodeInternalError);
  [apiClientMock stopMocking];
}

- (void)testRemoteConfigServiceRejectsDuplicateFilteredListContexts {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientArrayCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfigListForContextKeys:@[@"requested"] includeEmptyContextKey:NO completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientArrayCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    apiCompletion = [completion copy];
  });

  __block NSError *deliveredError = nil;
  [service loadRemoteConfigList:@[@"requested"] includeEmptyContextKey:NO completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredError = error;
  }];
  apiCompletion(@[
    QONTestRemoteConfigResponse(@"first", @"requested"),
    QONTestRemoteConfigResponse(@"second", @"requested"),
  ], nil);

  XCTAssertEqual(deliveredError.code, QONErrorCodeInternalError);
  [apiClientMock stopMocking];
}

- (void)testRemoteConfigServiceRejectsDuplicateFullListContexts {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientArrayCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfigList:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientArrayCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:2];
    apiCompletion = [completion copy];
  });

  __block NSError *deliveredError = nil;
  [service loadRemoteConfigList:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredError = error;
  }];
  apiCompletion(@[
    QONTestRemoteConfigResponse(@"first", @"duplicate"),
    QONTestRemoteConfigResponse(@"second", @"duplicate"),
  ], nil);

  XCTAssertEqual(deliveredError.code, QONErrorCodeInternalError);
  [apiClientMock stopMocking];
}

- (void)testRemoteConfigServiceAcceptsUniqueFilteredSubsetAndOptionalEmptyContext {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientArrayCompletionHandler apiCompletion = nil;
  OCMStub(([apiClientMock loadRemoteConfigListForContextKeys:@[@"first", @"omitted"] includeEmptyContextKey:YES completion:[OCMArg any]])).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientArrayCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:4];
    apiCompletion = [completion copy];
  });

  __block QONRemoteConfigList *deliveredList = nil;
  __block NSError *deliveredError = nil;
  [service loadRemoteConfigList:@[@"first", @"omitted"] includeEmptyContextKey:YES completion:^(QONRemoteConfigList * _Nullable list, NSError * _Nullable error) {
    deliveredList = list;
    deliveredError = error;
  }];
  apiCompletion(@[
    QONTestRemoteConfigResponse(@"first", @"first"),
    QONTestRemoteConfigResponse(@"empty", @""),
  ], nil);

  XCTAssertEqual(deliveredList.remoteConfigs.count, 2);
  XCTAssertNil(deliveredError);
  [apiClientMock stopMocking];
}

- (void)testFrozenAssignmentTypeIsPubliclyMappedDescribedAndUnknownRemainsForwardCompatible {
  QONRemoteConfigurationAssignmentType frozenType = QONRemoteConfigurationAssignmentTypeFrozen;
  XCTAssertEqual(frozenType, 2);
  XCTAssertEqual(QONRemoteConfigurationAssignmentTypeManual, 1);

  QONRemoteConfigMapper *mapper = [QONRemoteConfigMapper new];
  NSDictionary *baseSource = @{
    @"uid": @"source",
    @"name": @"source",
    @"type": @"remote_configuration",
  };
  NSMutableDictionary *frozenSource = [baseSource mutableCopy];
  frozenSource[@"assignment_type"] = @"frozen";
  QONRemoteConfig *frozenConfig = [mapper mapRemoteConfig:@{@"payload": @{}, @"source": frozenSource}];
  XCTAssertEqual(frozenConfig.source.assignmentType, QONRemoteConfigurationAssignmentTypeFrozen);
  XCTAssertTrue([frozenConfig.source.description containsString:@"assignmentType=frozen"]);

  NSMutableDictionary *futureSource = [baseSource mutableCopy];
  futureSource[@"assignment_type"] = @"future_server_value";
  QONRemoteConfig *futureConfig = [mapper mapRemoteConfig:@{@"payload": @{}, @"source": futureSource}];
  XCTAssertEqual(futureConfig.source.assignmentType, QONRemoteConfigurationAssignmentTypeUnknown);
}

- (void)testRemoteConfigServiceAcceptsFrozenAndRejectsUnknownFutureAssignment {
  QONRemoteConfigService *service = [QONRemoteConfigService new];
  id apiClientMock = OCMClassMock([QNAPIClient class]);
  service.apiClient = apiClientMock;
  __block QNAPIClientDictCompletionHandler apiCompletion = nil;
  OCMStub([apiClientMock loadRemoteConfig:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    __unsafe_unretained QNAPIClientDictCompletionHandler completion = nil;
    [invocation getArgument:&completion atIndex:3];
    apiCompletion = [completion copy];
  });
  NSDictionary *source = @{
    @"uid": @"source",
    @"name": @"source",
    @"type": @"remote_configuration",
    @"context_key": @"ctx",
  };

  __block QONRemoteConfig *frozenConfig = nil;
  __block NSError *frozenError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    frozenConfig = config;
    frozenError = error;
  }];
  NSMutableDictionary *frozenSource = [source mutableCopy];
  frozenSource[@"assignment_type"] = @"frozen";
  apiCompletion(@{ @"payload": @{}, @"source": frozenSource }, nil);
  XCTAssertEqual(frozenConfig.source.assignmentType, QONRemoteConfigurationAssignmentTypeFrozen);
  XCTAssertNil(frozenError);

  __block QONRemoteConfig *futureConfig = nil;
  __block NSError *futureError = nil;
  [service loadRemoteConfig:@"ctx" completion:^(QONRemoteConfig * _Nullable config, NSError * _Nullable error) {
    futureConfig = config;
    futureError = error;
  }];
  NSMutableDictionary *futureSource = [source mutableCopy];
  futureSource[@"assignment_type"] = @"future_server_value";
  apiCompletion(@{ @"payload": @{}, @"source": futureSource }, nil);
  XCTAssertNil(futureConfig);
  XCTAssertEqual(futureError.code, QONErrorCodeInternalError);
  [apiClientMock stopMocking];
}

- (void)testTransientRemoteConfigErrorsIncludeTimeoutConnectionLossAndServerFailures {
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDNSLookupFailed userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCallIsActive userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataNotAllowed userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:QonversionErrorDomain code:503 userInfo:nil] shouldFireFallback]);
  XCTAssertTrue([[NSError errorWithDomain:QonversionErrorDomain code:QONErrorCodeInternalError userInfo:nil] shouldFireFallback]);
  XCTAssertFalse([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil] shouldFireFallback]);
  XCTAssertFalse([[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil] shouldFireFallback]);
  XCTAssertFalse([[NSError errorWithDomain:QonversionErrorDomain code:401 userInfo:nil] shouldFireFallback]);
  XCTAssertFalse([[NSError errorWithDomain:QonversionErrorDomain code:404 userInfo:nil] shouldFireFallback]);
  XCTAssertFalse([[NSError errorWithDomain:NSPOSIXErrorDomain code:503 userInfo:nil] shouldFireFallback]);
}

@end
