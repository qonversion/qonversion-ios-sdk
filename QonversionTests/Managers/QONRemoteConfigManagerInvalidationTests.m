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
#import "QNProductCenterManager.h"
#import "QNUserPropertiesManager.h"
#import "QONRemoteConfig.h"
#import "QONRemoteConfigList+Protected.h"
#import "QONRemoteConfigurationSource.h"
#import "QONFallbackService.h"
#import "QONFallbackObject.h"

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
@property (atomic, assign) NSUInteger cacheGeneration;

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

@end
