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
  XCTAssertNotNil([controller subscribeOnConfigUpdate:^(__unused QONRemoteConfigUpdate *update) {}]);
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
  XCTAssertEqual(environment.readGuardAssertions, 0u);
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

#pragma mark - Context fingerprint
//
// The fingerprint hashes mutable targeting context (app/OS version, locale,
// purchases, properties); it rotates legitimately and MUST NOT be pinned
// across fetches. Identity isolation is the session's job.

- (QONRemoteConfigV2Scope *)scopeForUser:(NSString *)canonicalUserID {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:QONRCPubProjectKey
                                                environment:QONRCPubEnvironmentUID
                                            canonicalUserID:canonicalUserID];
}

/** The expectation the coordinator always states: no fingerprint at all. */
- (QONRemoteConfigV2EnvelopeExpectation *)openExpectation {
  return [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:QONRCPubProjectID environmentUID:QONRCPubEnvironmentUID];
}

- (NSString *)alphaValues:(NSString *)raw variation:(NSString *)variation {
  return [self alphaValues:raw variation:variation policy:@"on_next_activate"];
}

- (void)enqueueForeignRelease:(QONRCPubEnvironment *)environment
                   releaseUID:(NSString *)releaseUID
                       number:(NSInteger)number
                       values:(NSString *)values {
  NSData *body = QONRCPubSnapshotBodyWithFingerprint(releaseUID, number, values,
                                                     QONRCPubOtherFingerprint);
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
}

- (void)testAFingerprintRotationBetweenFetchesIsAdmitted {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;

  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"]];
  XCTAssertTrue([self runFetch:environment activate:YES deliveries:NULL].changed);

  // An app update, a locale change, a purchase or a property write is enough to
  // move the fingerprint. The same user, the same scope, a different tag.
  [self enqueueForeignRelease:environment releaseUID:@"release-2" number:2
                       values:[self alphaValues:@"\"server-alpha-2\"" variation:@"variation-a2"]];
  XCTAssertTrue([self runFetch:environment activate:YES deliveries:NULL].changed);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-2");

  // And back again: the tag carries no ordering and no history.
  [self enqueueRelease:environment releaseUID:@"release-3" number:3
                values:[self alphaValues:@"\"server-alpha-3\"" variation:@"variation-a3"]];
  XCTAssertTrue([self runFetch:environment activate:YES deliveries:NULL].changed);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-3");
}

- (void)testAFingerprintRotationSurvivesARestart {
  QONRCPubEnvironment *first =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  [self enqueueRelease:first releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"]];
  XCTAssertTrue([self runFetch:first activate:YES deliveries:NULL].changed);

  // A restart is where an app update lands, so it is exactly where the
  // fingerprint is most likely to have moved. Nothing may refuse it.
  QONRCPubEnvironment *restarted = QONRCPubDormantEnvironment([self defaultsFixture]);
  restarted.storage = first.storage;
  XCTAssertTrue(QONRCPubInstallEngine(restarted, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                      @"user-a"));
  [self enqueueForeignRelease:restarted releaseUID:@"release-4" number:4
                       values:[self alphaValues:@"\"server-alpha-4\"" variation:@"variation-a4"]];
  XCTAssertTrue([self runFetch:restarted activate:YES deliveries:NULL].changed);
  XCTAssertEqualObjects([restarted.controller rawValueForKey:@"alpha"].value, @"server-alpha-4");
}

- (void)testAMalformedContextFingerprintIsRefused {
  XCTAssertTrue(QONRemoteConfigV2ValidContextFingerprint(QONRCPubFingerprint));
  XCTAssertFalse(QONRemoteConfigV2ValidContextFingerprint(nil));
  XCTAssertFalse(QONRemoteConfigV2ValidContextFingerprint(@""));
  XCTAssertFalse(QONRemoteConfigV2ValidContextFingerprint(
      [QONRCPubFingerprint substringToIndex:63]));
  XCTAssertFalse(QONRemoteConfigV2ValidContextFingerprint(
      [QONRCPubFingerprint stringByAppendingString:@"a"]));
  XCTAssertFalse(QONRemoteConfigV2ValidContextFingerprint(QONRCPubFingerprint.uppercaseString));
  XCTAssertFalse(QONRemoteConfigV2ValidContextFingerprint(
      [@"g" stringByPaddingToLength:64 withString:@"g" startingAtIndex:0]));

  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"user-a"];

  NSData *malformed = QONRCPubSnapshotBodyWithFingerprint(@"release-1", 1,
      [self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"],
      QONRCPubFingerprint.uppercaseString);
  QONRemoteConfigV2AdmissionToken *bad =
      [manager beginAdmissionForScope:scope expectation:[self openExpectation]];
  XCTAssertEqual([manager admitBody:malformed strongETag:QONRCPubStrongETag(malformed)
                     admissionToken:bad], QONRemoteConfigV2TransitionStatusRejected);
  XCTAssertEqual([environment.controller rawValueForKey:@"alpha"].source,
                 QONRemoteConfigValueSourceFallback);

  NSData *wellFormed = QONRCPubSnapshotBody(@"release-1", 1,
      [self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"]);
  QONRemoteConfigV2AdmissionToken *good =
      [manager beginAdmissionForScope:scope expectation:[self openExpectation]];
  XCTAssertEqual([manager admitBody:wellFormed strongETag:QONRCPubStrongETag(wellFormed)
                     admissionToken:good], QONRemoteConfigV2TransitionStatusAccepted);
}

// A stated fingerprint constrains that one call and nothing beyond it. It is
// not a pin: it never outlives the admission token that carried it.
- (void)testAStatedFingerprintConstrainsOnlyItsOwnCall {
  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"user-a"];
  NSData *body = QONRCPubSnapshotBody(@"release-1", 1,
      [self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"]);
  NSString *eTag = QONRCPubStrongETag(body);

  QONRemoteConfigV2AdmissionToken *mismatched = [manager beginAdmissionForScope:scope
      expectation:[[QONRemoteConfigV2EnvelopeExpectation alloc]
          initWithProjectID:QONRCPubProjectID
             environmentUID:QONRCPubEnvironmentUID
         contextFingerprint:QONRCPubOtherFingerprint]];
  XCTAssertEqual([manager admitBody:body strongETag:eTag admissionToken:mismatched],
                 QONRemoteConfigV2TransitionStatusRejected);

  QONRemoteConfigV2AdmissionToken *open =
      [manager beginAdmissionForScope:scope expectation:[self openExpectation]];
  XCTAssertEqual([manager admitBody:body strongETag:eTag admissionToken:open],
                 QONRemoteConfigV2TransitionStatusAccepted);
}

- (void)testScopeIsolationIsKeyedStorageNotTheFingerprint {
  QONRemoteConfigV2Scope *userA = [self scopeForUser:@"user-a"];
  QONRemoteConfigV2Scope *userB = [self scopeForUser:@"user-b"];
  XCTAssertNotEqualObjects([QONRemoteConfigV2GatewaySessionStore storageKeyForScope:userA],
                           [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:userB]);

  QONRCPubEnvironment *environment =
      [self configuredEnvironmentWithBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
              minimumFetchIntervalMilliseconds:0];
  QONRemoteConfigController *controller = environment.controller;

  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-a\"" variation:@"variation-a1"]];
  XCTAssertTrue([self runFetch:environment activate:YES deliveries:NULL].changed);

  // The second identity's response carries a different fingerprint, as it
  // would in production. Isolation comes from the scope, not from that.
  [self enqueueForeignRelease:environment releaseUID:@"release-2" number:2
                       values:[self alphaValues:@"\"server-alpha-b\"" variation:@"variation-b1"]];
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  XCTAssertTrue(controller.activate);
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-b");

  [controller switchToCanonicalUserID:@"user-a"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  [controller activate];
  XCTAssertEqualObjects([controller rawValueForKey:@"alpha"].value, @"server-alpha-a");
}

// The controller never touches the install date itself: the transport owns it.
// This pins the device-scoped storage contract the identity switch relies on.
- (void)testDeviceInstallDateIsDeviceScopedAcrossIdentities {
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

#pragma mark - Subscriptions across configuration

- (void)testASubscriptionMadeWhileDormantIsReplayedAfterConfiguration {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment([self defaultsFixture]);
  QONRemoteConfigController *controller = environment.controller;

  NSMutableArray<QONRemoteConfigUpdate *> *kept = [NSMutableArray new];
  NSMutableArray<QONRemoteConfigUpdate *> *dropped = [NSMutableArray new];
  id keptToken = [controller subscribeOnConfigUpdate:^(QONRemoteConfigUpdate *update) {
    [kept addObject:update];
  }];
  id droppedToken = [controller subscribeOnConfigUpdate:^(QONRemoteConfigUpdate *update) {
    [dropped addObject:update];
  }];
  XCTAssertNotNil(keptToken);
  XCTAssertNotNil(droppedToken);
  XCTAssertNotEqualObjects(keptToken, droppedToken);
  [controller unsubscribe:droppedToken];

  XCTAssertTrue(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                      @"user-a"));
  [self enqueueRelease:environment releaseUID:@"release-1" number:1
                values:[self alphaValues:@"\"server-alpha-1\"" variation:@"variation-a1"
                                  policy:@"immediate"]];
  [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertEqual(kept.count, 1u);
  XCTAssertEqual(dropped.count, 0u);

  [controller unsubscribe:keptToken];
  [controller unsubscribe:@"not-a-token"];
  [self enqueueRelease:environment releaseUID:@"release-2" number:2
                values:[self alphaValues:@"\"server-alpha-2\"" variation:@"variation-a2"
                                  policy:@"immediate"]];
  [self runFetch:environment activate:NO deliveries:NULL];
  XCTAssertEqual(kept.count, 1u);
}

#pragma mark - Real assembly

- (void)testTheRealAssemblyInstallsWithoutTouchingTheNetwork {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment([self defaultsFixture]);
  QONRemoteConfigController *controller = environment.controller;
  QONRCPubStorage *storage = [QONRCPubStorage new];

  // A project the caller cannot name yet keeps the coordinator unbound, so the
  // real assembly is exercised end to end with no request ever leaving.
  BOOL configured = [controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                        projectToken:@"project-token"
                                          projectKey:QONRCPubProjectKey
                                         environment:QONRCPubEnvironmentUID
                                     canonicalUserID:@"user-a"
                                  readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                        localStorage:storage
                               clientContextProvider:[QONRCPubContextProvider new]
                                           projectID:0];
  XCTAssertTrue(configured);
  XCTAssertTrue(controller.isConfigured);

  // configureWithBaseURL: owns its own identity queue, so wait on the effect.
  XCTestExpectation *bound = [self expectationWithDescription:@"scope bound"];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{ [bound fulfill]; });
  [self waitForExpectationsWithTimeout:2 handler:nil];
  // Nothing is bound, so nothing may reach the network or the token storage.
  XCTAssertEqual(storage.objects.count, 0u);

  XCTAssertFalse([controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                     projectToken:@"project-token"
                                       projectKey:QONRCPubProjectKey
                                      environment:QONRCPubEnvironmentUID
                                  canonicalUserID:@"user-a"
                               readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                     localStorage:storage
                            clientContextProvider:[QONRCPubContextProvider new]
                                        projectID:0]);

  XCTAssertEqual([controller rawValueForKey:@"alpha"].source,
                 QONRemoteConfigValueSourceFallback);
  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = [self runFetch:environment activate:NO
                                          deliveries:&deliveries];
  XCTAssertEqual(deliveries, 1u);
  XCTAssertEqual(result.status, QONRemoteConfigFetchStatusFailed);
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
