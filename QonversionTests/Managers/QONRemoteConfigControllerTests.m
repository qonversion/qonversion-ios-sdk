//
//  QONRemoteConfigControllerTests.m
//  QonversionTests
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//
//  The headless mirror of this suite is QONRemoteConfigControllerHarness.m.
//

#import <XCTest/XCTest.h>

#import "QONRemoteConfigControllerFixtures.h"
#import "QONRemoteConfigV2DeviceInstallDate.h"

@interface QONRemoteConfigControllerTests : XCTestCase
@end

@implementation QONRemoteConfigControllerTests

#pragma mark - Helpers

- (NSArray<NSArray<NSString *> *> *)defaultsFixture {
  // Keys must be in ascending UTF-8 byte order.
  return @[
    @[@"alpha", @"variation-fallback-alpha", @"\"fallback-alpha\""],
    @[@"gamma", @"variation-fallback-gamma", @"\"fallback-gamma\""],
  ];
}

- (NSData *)releaseBody:(NSString *)releaseUID
                 number:(NSInteger)number
                 values:(NSString *)values {
  return QONRCPubSnapshotBody(releaseUID, number, values);
}

- (void)enqueueRelease:(QONRCPubEnvironment *)environment
            releaseUID:(NSString *)releaseUID
                number:(NSInteger)number
                values:(NSString *)values {
  NSData *body = [self releaseBody:releaseUID number:number values:values];
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
}

- (QONRemoteConfigFetchResult *)runFetch:(QONRCPubEnvironment *)environment
                                activate:(BOOL)activate
                              deliveries:(NSUInteger *)deliveries {
  __block QONRemoteConfigFetchResult *captured = nil;
  __block NSUInteger count = 0;
  QONRemoteConfigFetchCompletion completion = ^(QONRemoteConfigFetchResult *result) {
    captured = result;
    count += 1;
  };
  if (activate) {
    [environment.controller fetchAndActivateWithTimeout:0 completion:completion];
  } else {
    [environment.controller fetchWithTimeout:0 completion:completion];
  }
  [environment drain];
  if (deliveries) *deliveries = count;
  return captured;
}

- (QONRCPubEnvironment *)configuredEnvironmentWithBuildMode:
    (QONRemoteConfigV2ReadGuardBuildMode)buildMode
                              minimumFetchIntervalMilliseconds:(int64_t)minimumInterval {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment([self defaultsFixture]);
  XCTAssertTrue(QONRCPubInstallEngine(environment, buildMode, minimumInterval, @"user-a"));
  return environment;
}

- (NSString *)alphaValues:(NSString *)raw variation:(NSString *)variation policy:(NSString *)policy {
  return [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(raw, variation, policy, @"null")];
}

#pragma mark - Dormant surface

- (void)testDormantSurfaceServesBundledDefaultsAndRefusesToFetch {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment([self defaultsFixture]);
  QONRemoteConfigController *controller = environment.controller;

  XCTAssertFalse(controller.isConfigured);
  XCTAssertEqualObjects([controller bundledFallbackValueForKey:@"alpha"], @"fallback-alpha");
  XCTAssertTrue(QONRCPubDataEquals([controller bundledFallbackRawValueForKey:@"alpha"],
                                   QONRCPubUTF8(@"\"fallback-alpha\"")));
  XCTAssertNil([controller bundledFallbackValueForKey:@"missing"]);

  XCTAssertEqual(controller.current.allKeys.count, 2u);
  QONRemoteConfigValue *value = [controller rawValueForKey:@"alpha"];
  XCTAssertEqual(value.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(value.value, @"fallback-alpha");

  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = [self runFetch:environment activate:NO
                                          deliveries:&deliveries];
  XCTAssertEqual(deliveries, 1u);
  XCTAssertEqual(result.status, QONRemoteConfigFetchStatusUnavailable);
  XCTAssertFalse(result.changed);
  XCTAssertFalse(result.hasPendingActivation);
  XCTAssertNotNil(result.snapshot);
  XCTAssertNil([controller subscribeOnConfigUpdate:^(__unused QONRemoteConfigUpdate *update) {}]);
  XCTAssertFalse(controller.activate);
}

#pragma mark - Fetch and activate

- (void)testFetchStoresACandidateAndActivatePublishesItAtomically {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];

  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = [self runFetch:environment activate:NO
                                          deliveries:&deliveries];
  XCTAssertEqual(deliveries, 1u);
  XCTAssertEqual(result.status, QONRemoteConfigFetchStatusFetched);
  XCTAssertFalse(result.changed);
  XCTAssertTrue(result.hasPendingActivation);
  XCTAssertEqual(environment.readGuardAssertions, 0u);

  XCTAssertEqual([controller rawValueForKey:@"alpha"].source,
                 QONRemoteConfigValueSourceFallback);
  XCTAssertEqual(environment.readGuardAssertions, 1u);

  XCTAssertTrue(controller.activate);
  XCTAssertFalse(controller.activate);

  QONRemoteConfigValue *value = [controller valueForKey:@"alpha" decoder:QONRCPubAnyDecoder()];
  XCTAssertEqual(value.source, QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects(value.value, @"server-alpha-1");
  XCTAssertEqualObjects(value.variationUID, @"variation-a1");
}

- (void)testFetchAndActivatePublishesInOneCall {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];

  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = [self runFetch:environment activate:YES
                                          deliveries:&deliveries];
  XCTAssertEqual(deliveries, 1u);
  XCTAssertEqual(result.status, QONRemoteConfigFetchStatusFetched);
  XCTAssertTrue(result.changed);
  XCTAssertFalse(result.hasPendingActivation);
  XCTAssertEqualObjects([result.snapshot rawValueForKey:@"alpha"].value, @"server-alpha-1");
  XCTAssertEqual(environment.readGuardAssertions, 0u);

  [environment.transport enqueueFailure];
  QONRemoteConfigFetchResult *failed = [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertEqual(failed.status, QONRemoteConfigFetchStatusFailed);
  XCTAssertFalse(failed.changed);
  XCTAssertEqualObjects([failed.snapshot rawValueForKey:@"alpha"].value, @"server-alpha-1");
}

#pragma mark - Source ladder

- (void)testSourceLadderWalksServerThenCacheThenFallback {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;

  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];
  [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertTrue(controller.activate);
  XCTAssertEqual([controller valueForKey:@"alpha"
                                 decoder:QONRCPubPrefixDecoder(@"server-")].source,
                 QONRemoteConfigValueSourceServer);

  [self enqueueRelease:environment releaseUID:@"release-2" number:2
                values:[self alphaValues:@"\"rejected-alpha\"" variation:@"variation-a2"
                                  policy:@"on_next_activate"]];
  [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertTrue(controller.activate);

  QONRemoteConfigValue *cached = [controller valueForKey:@"alpha"
                                                 decoder:QONRCPubPrefixDecoder(@"server-")];
  XCTAssertEqual(cached.source, QONRemoteConfigValueSourceCache);
  XCTAssertEqualObjects(cached.value, @"server-alpha-1");

  QONRemoteConfigValue *raw = [controller rawValueForKey:@"alpha"];
  XCTAssertEqual(raw.source, QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects(raw.value, @"rejected-alpha");

  QONRemoteConfigValue *fallback = [controller valueForKey:@"gamma"
                                                   decoder:QONRCPubAnyDecoder()];
  XCTAssertEqual(fallback.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(fallback.value, @"fallback-gamma");

  XCTAssertNil([controller valueForKey:@"nowhere" decoder:QONRCPubAnyDecoder()]);
  XCTAssertNil([controller valueForKey:@"gamma" decoder:QONRCPubPrefixDecoder(@"server-")]);
}

#pragma mark - Timeout

- (void)testTimeoutCompletesOnBestAvailableWhileTheRequestKeepsRunning {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];
  [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertTrue(controller.activate);

  __block QONRemoteConfigFetchResult *captured = nil;
  __block NSUInteger deliveries = 0;
  environment.transport.holdNextRequest = YES;
  [controller fetchWithTimeout:0.05 completion:^(QONRemoteConfigFetchResult *result) {
    captured = result;
    deliveries += 1;
  }];
  [environment drain];
  XCTAssertEqual(deliveries, 0u);

  XCTAssertTrue([environment.scheduler fireFirstPending]);
  [environment drain];
  XCTAssertEqual(deliveries, 1u);
  XCTAssertEqual(captured.status, QONRemoteConfigFetchStatusTimedOut);
  XCTAssertEqualObjects(captured.snapshot.releaseUID, @"release-1");
  XCTAssertEqual([captured.snapshot rawValueForKey:@"alpha"].source,
                 QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects([captured.snapshot rawValueForKey:@"alpha"].value, @"server-alpha-1");
  XCTAssertFalse(captured.hasPendingActivation);
  XCTAssertEqual(environment.readGuardAssertions, 0u);

  NSData *late = [self releaseBody:@"release-2" number:2
                            values:[self alphaValues:@"\"server-alpha-2\""
                                           variation:@"variation-a2"
                                              policy:@"on_next_activate"]];
  XCTAssertTrue([environment.transport releaseHeldWithBody:late
                                                strongETag:QONRCPubStrongETag(late)]);
  [environment drain];
  XCTAssertEqual(deliveries, 1u);

  XCTAssertTrue(controller.activate);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-2");
}

#pragma mark - Updates

- (void)testSubscribeReportsChangedKeysAndImmediateSwapsTheWholeRelease {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];
  [self runFetch:environment activate:YES deliveries:NULL];

  NSMutableArray<QONRemoteConfigUpdate *> *updates = [NSMutableArray new];
  id token = [controller subscribeOnConfigUpdate:^(QONRemoteConfigUpdate *update) {
    [updates addObject:update];
  }];
  XCTAssertNotNil(token);

  NSString *values = [NSString stringWithFormat:@"\"alpha\":%@,\"delta\":%@",
      QONRCPubItem(@"\"server-alpha-2\"", @"variation-a2", @"immediate",
                   @"{\"resetNavigation\":true}"),
      QONRCPubItem(@"\"server-delta\"", @"variation-d1", @"on_next_activate", @"null")];
  [self enqueueRelease:environment releaseUID:@"release-2" number:2 values:values];

  QONRemoteConfigFetchResult *result = [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertTrue(result.changed);
  XCTAssertFalse(result.hasPendingActivation);
  XCTAssertEqual(updates.count, 1u);
  NSSet *expectedChangedKeys = [NSSet setWithArray:@[@"alpha", @"delta"]];
  XCTAssertEqualObjects(updates.firstObject.changedKeys, expectedChangedKeys);
  XCTAssertEqualObjects(updates.firstObject.metadataByKey[@"alpha"][@"resetNavigation"], @YES);

  QONRemoteConfigValue *sibling = [controller rawValueForKey:@"delta"];
  XCTAssertEqual(sibling.source, QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects(sibling.value, @"server-delta");
  XCTAssertEqual([controller rawValueForKey:@"alpha"].applyPolicy,
                 QONRemoteConfigApplyPolicyImmediate);
  XCTAssertFalse(controller.activate);

  [controller unsubscribe:token];
  [self enqueueRelease:environment releaseUID:@"release-3" number:3
                values:[self alphaValues:@"\"server-alpha-3\"" variation:@"variation-a3"
                                  policy:@"immediate"]];
  [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertEqual(updates.count, 1u);
}

#pragma mark - Identity

- (void)testIdentitySwitchDropsTheOldScopeImmediatelyAndForcesAFetch {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:3600000];
  QONRemoteConfigController *controller = environment.controller;
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];
  [self runFetch:environment activate:YES deliveries:NULL];
  XCTAssertEqualObjects(controller.current.releaseUID, @"release-1");

  QONRemoteConfigFetchResult *throttled = [self runFetch:environment activate:NO
                                              deliveries:NULL];
  XCTAssertEqual(throttled.status, QONRemoteConfigFetchStatusThrottled);

  NSUInteger requestsBefore = environment.transport.requests.count;
  [self enqueueRelease:environment releaseUID:@"release-9" number:9
                values:[self alphaValues:@"\"server-alpha-b\"" variation:@"variation-b1"
                                  policy:@"on_next_activate"]];

  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeLogout];
  XCTAssertEqualObjects(controller.current.releaseUID, @"release-bundle");
  XCTAssertEqual([controller rawValueForKey:@"alpha"].source,
                 QONRemoteConfigValueSourceFallback);

  [environment settleIdentity];
  XCTAssertEqual(environment.transport.requests.count, requestsBefore + 1);
  XCTAssertTrue(controller.activate);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-b");

  NSUInteger requestsAfterSwitch = environment.transport.requests.count;
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  XCTAssertEqual(environment.transport.requests.count, requestsAfterSwitch);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-b");

  [controller switchToCanonicalUserID:nil
                               change:QONRemoteConfigControllerIdentityChangeLogout];
  XCTAssertEqualObjects(controller.current.releaseUID, @"release-bundle");
}

- (void)testASupersededIdentitySwitchCanNeverRebindItsScope {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;
  [self enqueueRelease:environment releaseUID:@"release-c" number:3
                values:[self alphaValues:@"\"server-alpha-c\"" variation:@"variation-c1"
                                  policy:@"on_next_activate"]];

  NSUInteger requestsBefore = environment.transport.requests.count;
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [controller switchToCanonicalUserID:@"user-c"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];

  XCTAssertEqual(environment.transport.requests.count, requestsBefore + 1);
  XCTAssertTrue(controller.activate);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-c");
}

- (void)testDeviceInstallDateSurvivesAnIdentityChange {
  QONRCPubStorage *storage = [QONRCPubStorage new];
  QONRCPubClock *clock = [QONRCPubClock new];
  clock.now = 1700000000000;
  QONRemoteConfigV2DeviceInstallDateProvider *provider =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc]
          initWithLocalStorage:storage systemInstallDateSeconds:@(1500000000) clock:clock];
  NSNumber *first = [provider deviceInstalledAtSeconds];
  XCTAssertEqualObjects(first, @(1500000000));
  XCTAssertNotNil(storage.objects[QONRemoteConfigV2DeviceInstallDateStorageKey]);

  QONRemoteConfigV2DeviceInstallDateProvider *afterLogout =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc]
          initWithLocalStorage:storage systemInstallDateSeconds:@(1690000000) clock:clock];
  XCTAssertEqualObjects([afterLogout deviceInstalledAtSeconds], first);
}

#pragma mark - Read guard

- (void)testReleaseBuildActivatesOnceSilentlyOnAFirstRead {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeRelease
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"on_next_activate"]];
  QONRemoteConfigFetchResult *result = [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertTrue(result.hasPendingActivation);

  __block QONRemoteConfigFetchResult *timedOut = nil;
  environment.transport.holdNextRequest = YES;
  [controller fetchWithTimeout:0.05 completion:^(QONRemoteConfigFetchResult *fetched) {
    timedOut = fetched;
  }];
  [environment drain];
  XCTAssertTrue([environment.scheduler fireFirstPending]);
  [environment drain];
  XCTAssertEqual(timedOut.status, QONRemoteConfigFetchStatusTimedOut);
  XCTAssertEqual([timedOut.snapshot rawValueForKey:@"alpha"].source,
                 QONRemoteConfigValueSourceFallback);

  QONRemoteConfigValue *value = [controller rawValueForKey:@"alpha"];
  XCTAssertEqual(environment.readGuardAssertions, 0u);
  XCTAssertEqual(value.source, QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects(value.value, @"server-alpha-1");
  XCTAssertFalse(controller.activate);
}

@end
