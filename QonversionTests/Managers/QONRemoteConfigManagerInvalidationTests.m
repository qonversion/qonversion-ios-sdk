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

/*
 * Contract tests for the attach/detach cache invalidation (DEV-1231).
 *
 * An attach/detach is addressed by experiment/configuration id, and the SDK
 * cannot know which context key that entity serves — so EVERY cached config
 * must be dropped (named keys included), loading states must survive with
 * their pending completions, and an in-flight load must not re-cache a
 * pre-attach evaluation (generation guard).
 */

@interface QONRemoteConfigManager (InvalidationContractPrivate)

@property (nonatomic, strong) NSMutableDictionary<NSString *, QONRemoteConfigLoadingState *> *loadingStates;
@property (atomic, assign) NSUInteger cacheGeneration;

@end

@interface QONRemoteConfigManagerInvalidationTests : XCTestCase

@property (nonatomic, strong) id mockService;
@property (nonatomic, strong) id mockProductCenterManager;
@property (nonatomic, strong) id mockUserPropertiesManager;
@property (nonatomic, strong) QONRemoteConfigManager *manager;

@end

@implementation QONRemoteConfigManagerInvalidationTests

- (void)setUp {
  [super setUp];

  self.manager = [QONRemoteConfigManager new];

  self.mockService = OCMClassMock([QONRemoteConfigService class]);
  self.mockProductCenterManager = OCMClassMock([QNProductCenterManager class]);
  self.mockUserPropertiesManager = OCMClassMock([QNUserPropertiesManager class]);

  self.manager.remoteConfigService = self.mockService;
  self.manager.productCenterManager = self.mockProductCenterManager;
  self.manager.userPropertiesManager = self.mockUserPropertiesManager;
}

- (void)tearDown {
  [self.mockService stopMocking];
  [self.mockProductCenterManager stopMocking];
  [self.mockUserPropertiesManager stopMocking];
  self.manager = nil;

  [super tearDown];
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

- (void)testEveryAttachAndDetachEntryPointInvalidatesNamedKeyCachedConfigs {
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
}

- (void)testAttachInvalidationPreventsInFlightLoadFromReCachingStaleConfig {
  // given - the user is stable and a single-key load is in flight
  OCMStub([self.mockProductCenterManager isUserStable]).andReturn(YES);
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

  __block QONRemoteConfig *deliveredConfig = nil;
  [self.manager obtainRemoteConfigWithContextKey:@"ctx"
                                      completion:^(QONRemoteConfig * _Nullable remoteConfig, NSError * _Nullable error) {
    deliveredConfig = remoteConfig;
  }];
  XCTAssertNotNil(serviceCompletion, @"the load must reach the service");

  // when - the attach invalidates mid-flight, then the pre-attach response lands
  [self.manager attachUserToRemoteConfiguration:@"config_id"
                                     completion:^(BOOL success, NSError * _Nullable error) {}];
  QONRemoteConfig *staleConfig = OCMClassMock([QONRemoteConfig class]);
  serviceCompletion(staleConfig, nil);

  // then - the stale evaluation is delivered to the waiting caller but must
  // NOT be re-cached; the state stays refetchable
  XCTAssertEqual(deliveredConfig, staleConfig);
  XCTAssertNil(self.manager.loadingStates[@"ctx"].loadedConfig);
  XCTAssertFalse(self.manager.loadingStates[@"ctx"].isInProgress);
}

@end
