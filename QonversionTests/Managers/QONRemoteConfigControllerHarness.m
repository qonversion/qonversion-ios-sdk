//
//  Headless mirror of QONRemoteConfigControllerTests.
//
//  XCTest needs a full Xcode install, so the public Remote Config surface is
//  also runnable from the command line, exactly like the earlier slices:
//
//    clang -fobjc-arc -o /tmp/rc-public-harness \
//      QonversionTests/Managers/QONRemoteConfigControllerHarness.m \
//      Sources/Qonversion/Public/QONRemoteConfigController.m \
//      Sources/Qonversion/Public/QONRemoteConfigFetchResult.m \
//      Sources/Qonversion/Public/QONRemoteConfigSnapshot.m \
//      Sources/Qonversion/Public/QONRemoteConfigValue.m \
//      Sources/Qonversion/Public/QONRemoteConfigUpdate.m \
//      Sources/Qonversion/Qonversion/Main/QONRemoteConfigV2Manager/*.m \
//      Sources/Qonversion/Qonversion/Core/QONRemoteConfigV2Store/*.m \
//      Sources/Qonversion/Qonversion/Services/QONRemoteConfigV2Transport/*.m \
//      Sources/Qonversion/Qonversion/Services/QONRemoteConfigFallbackStore/*.m \
//      $(find Sources -type d | sed 's/^/-I/') -framework Foundation
//

#import <Foundation/Foundation.h>

#import "QONRemoteConfigControllerFixtures.h"
#import "QONRemoteConfigV2DeviceInstallDate.h"

static NSUInteger failures = 0;
static NSUInteger checks = 0;
#define QON_CHECK(condition, message) do { checks += 1; if (!(condition)) { \
  failures += 1; fprintf(stderr, "FAIL: %s\n", message); } } while (0)

static NSArray<NSArray<NSString *> *> *DefaultsFixture(void) {
  // Keys must be in ascending UTF-8 byte order.
  return @[
    @[@"alpha", @"variation-fallback-alpha", @"\"fallback-alpha\""],
    @[@"gamma", @"variation-fallback-gamma", @"\"fallback-gamma\""],
  ];
}

static NSData *ReleaseBody(NSString *releaseUID, NSInteger number, NSString *values) {
  return QONRCPubSnapshotBody(releaseUID, number, values);
}

/** One `alpha` entry that only publishes on the next activate. */
static NSString *AlphaValues(NSString *raw, NSString *variationUID) {
  return [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(raw, variationUID, @"on_next_activate", @"null")];
}

/** Spins until the condition holds or the deadline passes. */
static BOOL WaitUntil(BOOL (^condition)(void)) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
  while (!condition()) {
    if ([NSDate.date compare:deadline] == NSOrderedDescending) return NO;
    [NSThread sleepForTimeInterval:0.005];
  }
  return YES;
}

/** Runs one fetch and returns its result, or nil when nothing was delivered. */
static QONRemoteConfigFetchResult *RunFetch(QONRCPubEnvironment *environment,
                                            NSTimeInterval timeout,
                                            BOOL activate,
                                            NSUInteger *deliveryCount) {
  __block QONRemoteConfigFetchResult *captured = nil;
  __block NSUInteger deliveries = 0;
  QONRemoteConfigFetchCompletion completion = ^(QONRemoteConfigFetchResult *result) {
    captured = result;
    deliveries += 1;
  };
  if (activate) {
    [environment.controller fetchAndActivateWithTimeout:timeout completion:completion];
  } else {
    [environment.controller fetchWithTimeout:timeout completion:completion];
  }
  [environment drain];
  if (deliveryCount) *deliveryCount = deliveries;
  return captured;
}

#pragma mark - Tests

static void TestDormantSurfaceServesBundledDefaultsAndRefusesToFetch(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QONRemoteConfigController *controller = environment.controller;

  QON_CHECK(!controller.isConfigured, "an unconfigured controller must report itself dormant");
  QON_CHECK([[controller bundledFallbackValueForKey:@"alpha"] isEqual:@"fallback-alpha"],
            "the bundled getter must work before configuration and before activate");
  QON_CHECK(QONRCPubDataEquals([controller bundledFallbackRawValueForKey:@"alpha"],
                               QONRCPubUTF8(@"\"fallback-alpha\"")),
            "the bundled raw getter must return the exact validated JSON bytes");
  QON_CHECK([controller bundledFallbackValueForKey:@"missing"] == nil,
            "an unknown bundled key must return nil, not a placeholder");

  QONRemoteConfigSnapshot *snapshot = controller.current;
  QON_CHECK(snapshot != nil && snapshot.allKeys.count == 2,
            "a dormant current must still expose the complete bundled key set");
  QONRemoteConfigValue *value = [controller rawValueForKey:@"alpha"];
  QON_CHECK(value != nil && value.source == QONRemoteConfigValueSourceFallback &&
                [value.value isEqual:@"fallback-alpha"],
            "a dormant read must resolve from the bundle and say so");

  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, NO, &deliveries);
  QON_CHECK(deliveries == 1 && result.status == QONRemoteConfigFetchStatusUnavailable,
            "a dormant fetch must complete once as unavailable");
  QON_CHECK(!result.changed && !result.hasPendingActivation && result.snapshot != nil,
            "a dormant fetch result must still carry a readable snapshot");
  QON_CHECK([controller subscribeOnConfigUpdate:^(__unused QONRemoteConfigUpdate *update) {}] != nil,
            "a dormant subscribe must be kept rather than silently dropped");
  QON_CHECK(!controller.activate, "a dormant activate must report no change");
}

static void TestFetchStoresACandidateAndActivatePublishesItAtomically(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install over the fake seams");
  QONRemoteConfigController *controller = environment.controller;

  NSData *body = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];

  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, NO, &deliveries);
  QON_CHECK(deliveries == 1 && result.status == QONRemoteConfigFetchStatusFetched,
            "a successful fetch must complete exactly once as fetched");
  QON_CHECK(!result.changed && result.hasPendingActivation,
            "a fetch must not change the active configuration by itself");
  QON_CHECK(environment.readGuardAssertions == 0,
            "the SDK's own delivery read must not consume the read-before-activate guard");

  QONRemoteConfigValue *beforeActivate = [controller rawValueForKey:@"alpha"];
  QON_CHECK(beforeActivate.source == QONRemoteConfigValueSourceFallback,
            "a read before activate must not see the fetched release");
  QON_CHECK(environment.readGuardAssertions == 1,
            "a debug read before activate must assert exactly once");

  QON_CHECK(controller.activate, "activating a fetched release must report a change");
  QON_CHECK(!controller.activate, "activating twice must report no further change");

  QONRemoteConfigValue *afterActivate = [controller valueForKey:@"alpha"
                                                        decoder:QONRCPubAnyDecoder()];
  QON_CHECK(afterActivate.source == QONRemoteConfigValueSourceServer &&
                [afterActivate.value isEqual:@"server-alpha-1"],
            "an activated key must read from the server release");
  QON_CHECK([afterActivate.variationUID isEqualToString:@"variation-a1"],
            "a resolved value must carry its variation");
}

static void TestSourceLadderWalksServerThenCacheThenFallback(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the ladder scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  RunFetch(environment, 0, NO, NULL);
  QON_CHECK(controller.activate, "the first release must activate");

  QONRemoteConfigValue *server = [controller valueForKey:@"alpha"
                                                 decoder:QONRCPubPrefixDecoder(@"server-")];
  QON_CHECK(server.source == QONRemoteConfigValueSourceServer,
            "an accepted served value must resolve as server");

  NSData *second = ReleaseBody(@"release-2", 2, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"rejected-alpha\"", @"variation-a2", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:second strongETag:QONRCPubStrongETag(second)];
  RunFetch(environment, 0, NO, NULL);
  QON_CHECK(controller.activate, "the second release must activate");

  QONRemoteConfigValue *cached = [controller valueForKey:@"alpha"
                                                 decoder:QONRCPubPrefixDecoder(@"server-")];
  QON_CHECK(cached.source == QONRemoteConfigValueSourceCache &&
                [cached.value isEqual:@"server-alpha-1"],
            "a rejected served value must fall back to the previously active value as cache");

  QONRemoteConfigValue *raw = [controller rawValueForKey:@"alpha"];
  QON_CHECK(raw.source == QONRemoteConfigValueSourceServer &&
                [raw.value isEqual:@"rejected-alpha"],
            "a raw read must bypass validation and report the served value");

  QONRemoteConfigValue *fallback = [controller valueForKey:@"gamma"
                                                   decoder:QONRCPubAnyDecoder()];
  QON_CHECK(fallback.source == QONRemoteConfigValueSourceFallback &&
                [fallback.value isEqual:@"fallback-gamma"],
            "a key the server never served must resolve from the bundle");

  QONRemoteConfigValue *unknown = [controller valueForKey:@"nowhere"
                                                  decoder:QONRCPubAnyDecoder()];
  QON_CHECK(unknown == nil, "an unknown key must resolve nowhere");

  QONRemoteConfigValue *neverDecodes = [controller valueForKey:@"gamma"
                                                       decoder:QONRCPubPrefixDecoder(@"server-")];
  QON_CHECK(neverDecodes == nil,
            "a key whose every candidate is rejected must resolve to nil, not to bad bytes");
}

static void TestTimeoutCompletesOnBestAvailableWhileTheRequestKeepsRunning(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the timeout scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  RunFetch(environment, 0, NO, NULL);
  QON_CHECK(controller.activate, "the baseline release must activate");

  __block QONRemoteConfigFetchResult *captured = nil;
  __block NSUInteger deliveries = 0;
  environment.transport.holdNextRequest = YES;
  [controller fetchWithTimeout:0.05 completion:^(QONRemoteConfigFetchResult *result) {
    captured = result;
    deliveries += 1;
  }];
  [environment drain];
  QON_CHECK(deliveries == 0, "a held request must not complete before its deadline");
  QON_CHECK([environment.scheduler fireFirstPending], "the deadline must have been scheduled");
  [environment drain];

  QON_CHECK(deliveries == 1 && captured.status == QONRemoteConfigFetchStatusTimedOut,
            "an elapsed deadline must complete the call exactly once as timed out");
  QON_CHECK([captured.snapshot.releaseUID isEqualToString:@"release-1"],
            "a timed-out call must hand back the best available configuration");
  QONRemoteConfigValue *best = [captured.snapshot rawValueForKey:@"alpha"];
  QON_CHECK(best.source == QONRemoteConfigValueSourceServer &&
                [best.value isEqual:@"server-alpha-1"],
            "a timed-out read must still carry the value source");
  QON_CHECK(!captured.hasPendingActivation,
            "a timed-out call cannot claim a pending activation it has not seen");
  QON_CHECK(environment.readGuardAssertions == 0,
            "a slow network must not raise the app's read-before-activate assertion");

  NSData *second = ReleaseBody(@"release-2", 2, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-2\"", @"variation-a2", @"on_next_activate", @"null")]);
  QON_CHECK([environment.transport releaseHeldWithBody:second
                                            strongETag:QONRCPubStrongETag(second)],
            "the request behind a timed-out call must still be in flight");
  [environment drain];
  QON_CHECK(deliveries == 1, "a late response must not deliver a second completion");

  QON_CHECK(controller.activate, "the release admitted after the timeout must be activatable");
  QONRemoteConfigValue *late = [controller rawValueForKey:@"alpha"];
  QON_CHECK([late.value isEqual:@"server-alpha-2"],
            "the background request's release must become readable after activate");
}

static void TestFetchAndActivatePublishesInOneCall(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the fetch-and-activate scenario");

  NSData *body = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];

  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, YES, &deliveries);
  QON_CHECK(deliveries == 1 && result.status == QONRemoteConfigFetchStatusFetched,
            "fetchAndActivate must complete once with the fetch outcome");
  QON_CHECK(result.changed && !result.hasPendingActivation,
            "fetchAndActivate must report the change and leave nothing pending");
  QON_CHECK([[result.snapshot rawValueForKey:@"alpha"].value isEqual:@"server-alpha-1"],
            "the delivered snapshot must already contain the activated release");
  QON_CHECK(environment.readGuardAssertions == 0,
            "fetchAndActivate must satisfy the read guard rather than trip it");

  [environment.transport enqueueFailure];
  QONRemoteConfigFetchResult *failed = RunFetch(environment, 0, NO, &deliveries);
  QON_CHECK(failed.status == QONRemoteConfigFetchStatusFailed && !failed.changed,
            "a failed fetch must report failure and change nothing");
  QON_CHECK([[failed.snapshot rawValueForKey:@"alpha"].value isEqual:@"server-alpha-1"],
            "a failed fetch must still hand back the last good configuration");
}

static void TestSubscribeReportsChangedKeysAndImmediateSwapsTheWholeRelease(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the subscription scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  RunFetch(environment, 0, YES, NULL);

  __block NSMutableArray<QONRemoteConfigUpdate *> *updates = [NSMutableArray new];
  id token = [controller subscribeOnConfigUpdate:^(QONRemoteConfigUpdate *update) {
    [updates addObject:update];
  }];
  QON_CHECK(token != nil, "a configured subscribe must return a token");

  NSString *values = [NSString stringWithFormat:@"\"alpha\":%@,\"delta\":%@",
      QONRCPubItem(@"\"server-alpha-2\"", @"variation-a2", @"immediate",
                   @"{\"resetNavigation\":true}"),
      QONRCPubItem(@"\"server-delta\"", @"variation-d1", @"on_next_activate", @"null")];
  NSData *second = ReleaseBody(@"release-2", 2, values);
  [environment.transport enqueueBody:second strongETag:QONRCPubStrongETag(second)];

  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, NO, NULL);
  QON_CHECK(result.changed && !result.hasPendingActivation,
            "an immediate release must apply without an activate call");
  QON_CHECK(updates.count == 1, "an immediate release must notify exactly once");
  NSSet *expected = [NSSet setWithArray:@[@"alpha", @"delta"]];
  QON_CHECK([updates.firstObject.changedKeys isEqualToSet:expected],
            "the update must report every key whose effective value changed");
  QON_CHECK([updates.firstObject.metadataByKey[@"alpha"][@"resetNavigation"] isEqual:@YES],
            "the update must carry the changed key's metadata");

  QONRemoteConfigValue *sibling = [controller rawValueForKey:@"delta"];
  QON_CHECK(sibling.source == QONRemoteConfigValueSourceServer &&
                [sibling.value isEqual:@"server-delta"],
            "an immediate apply must swap the whole release, not only the immediate key");
  QON_CHECK([controller rawValueForKey:@"alpha"].applyPolicy ==
                QONRemoteConfigApplyPolicyImmediate,
            "a resolved value must expose its apply policy");
  QON_CHECK(!controller.activate,
            "an already applied immediate release must not activate again");

  [controller unsubscribe:token];
  NSData *third = ReleaseBody(@"release-3", 3, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-3\"", @"variation-a3", @"immediate", @"null")]);
  [environment.transport enqueueBody:third strongETag:QONRCPubStrongETag(third)];
  RunFetch(environment, 0, NO, NULL);
  QON_CHECK(updates.count == 1, "an unsubscribed handler must stop receiving updates");
}

static void TestASubscriptionMadeWhileDormantIsReplayedAfterConfiguration(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QONRemoteConfigController *controller = environment.controller;

  NSMutableArray<QONRemoteConfigUpdate *> *kept = [NSMutableArray new];
  NSMutableArray<QONRemoteConfigUpdate *> *dropped = [NSMutableArray new];
  id keptToken = [controller subscribeOnConfigUpdate:^(QONRemoteConfigUpdate *update) {
    [kept addObject:update];
  }];
  id droppedToken = [controller subscribeOnConfigUpdate:^(QONRemoteConfigUpdate *update) {
    [dropped addObject:update];
  }];
  QON_CHECK(keptToken != nil && droppedToken != nil && keptToken != droppedToken,
            "each dormant subscription must get its own token");
  [controller unsubscribe:droppedToken];

  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the replay scenario");
  NSData *body = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"immediate", @"null")]);
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
  RunFetch(environment, 0, NO, NULL);

  QON_CHECK(kept.count == 1,
            "a subscription made while dormant must receive updates after configuration");
  QON_CHECK(dropped.count == 0,
            "a subscription cancelled while dormant must never be replayed");

  [controller unsubscribe:keptToken];
  [controller unsubscribe:@"not-a-token"];
  NSData *second = ReleaseBody(@"release-2", 2, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-2\"", @"variation-a2", @"immediate", @"null")]);
  [environment.transport enqueueBody:second strongETag:QONRCPubStrongETag(second)];
  RunFetch(environment, 0, NO, NULL);
  QON_CHECK(kept.count == 1, "a replayed subscription must still be cancellable");
}

static void TestIdentitySwitchDropsTheOldScopeImmediatelyAndForcesAFetch(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  // A long minimum interval: only a forced fetch can reach the transport again.
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug,
                                  3600000, @"user-a"),
            "the engine must install for the identity scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  RunFetch(environment, 0, YES, NULL);
  QON_CHECK([controller.current.releaseUID isEqualToString:@"release-1"],
            "the first identity must be reading its own release");

  QONRemoteConfigFetchResult *throttled = RunFetch(environment, 0, NO, NULL);
  QON_CHECK(throttled.status == QONRemoteConfigFetchStatusThrottled,
            "a plain fetch inside the minimum interval must be throttled");

  NSUInteger requestsBefore = environment.transport.requests.count;
  NSData *second = ReleaseBody(@"release-9", 9, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-b\"", @"variation-b1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:second strongETag:QONRCPubStrongETag(second)];

  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeLogout];
  QON_CHECK([controller.current.releaseUID isEqualToString:@"release-bundle"],
            "the retired identity's release must stop being readable before the call returns");
  QON_CHECK([controller rawValueForKey:@"alpha"].source == QONRemoteConfigValueSourceFallback,
            "a read right after a logout must resolve from the bundle");

  [environment settleIdentity];
  QON_CHECK(environment.transport.requests.count == requestsBefore + 1,
            "an identity change must force a fetch through the minimum-interval gate");
  QON_CHECK(environment.readGuardAssertions == 0,
            "an identity change must not accuse an app that already activated");
  QON_CHECK(controller.activate, "the new identity's release must activate");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-b"],
            "the new identity must read its own release");

  NSUInteger requestsAfterSwitch = environment.transport.requests.count;
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  QON_CHECK(environment.transport.requests.count == requestsAfterSwitch,
            "re-announcing the identity already bound must not refetch");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-b"],
            "re-announcing the identity already bound must not blank the configuration");

  [controller switchToCanonicalUserID:nil
                               change:QONRemoteConfigControllerIdentityChangeLogout];
  QON_CHECK([controller.current.releaseUID isEqualToString:@"release-bundle"],
            "an unbound surface must fall back to the bundle");
}

static void TestASupersededIdentitySwitchCanNeverRebindItsScope(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the superseded-switch scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *body = ReleaseBody(@"release-c", 3, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-c\"", @"variation-c1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];

  NSUInteger requestsBefore = environment.transport.requests.count;
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [controller switchToCanonicalUserID:@"user-c"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];

  QON_CHECK(environment.transport.requests.count == requestsBefore + 1,
            "a superseded switch must not issue its own fetch");
  QON_CHECK(controller.activate, "the surviving identity's release must activate");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-c"],
            "only the newest identity may end up bound");
}

#pragma mark - Context fingerprint pin

static QONRemoteConfigV2Scope *PinScope(NSString *canonicalUserID) {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:QONRCPubProjectKey
                                                environment:QONRCPubEnvironmentUID
                                            canonicalUserID:canonicalUserID];
}

static void TestContextPinStoreIsScopeKeyedAndValidatesWhatItReadsBack(void) {
  QONRCPubStorage *storage = [QONRCPubStorage new];
  QONRemoteConfigV2ContextPinStore *store =
      [[QONRemoteConfigV2ContextPinStore alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *userA = PinScope(@"user-a");
  QONRemoteConfigV2Scope *userB = PinScope(@"user-b");

  QON_CHECK([store contextFingerprintForScope:userA] == nil,
            "an unpinned scope must report no pin rather than a placeholder");
  QON_CHECK(![store storeContextFingerprint:@"not-a-fingerprint" forScope:userA],
            "a malformed fingerprint must never be pinned");
  QON_CHECK([store storeContextFingerprint:QONRCPubFingerprint forScope:userA],
            "a well-formed fingerprint must pin");
  QON_CHECK([[store contextFingerprintForScope:userA] isEqualToString:QONRCPubFingerprint],
            "a pinned scope must read its pin back");
  QON_CHECK([store contextFingerprintForScope:userB] == nil,
            "the pin must be keyed by the full scope, identity included");

  QONRemoteConfigV2ContextPinStore *reopened =
      [[QONRemoteConfigV2ContextPinStore alloc] initWithLocalStorage:storage];
  QON_CHECK([[reopened contextFingerprintForScope:userA] isEqualToString:QONRCPubFingerprint],
            "a pin must survive the store object that wrote it");

  NSString *key = [QONRemoteConfigV2ContextPinStore storageKeyForScope:userA];
  storage.objects[key] = @{@"schema_version": @1, @"scope_key": key,
                           @"context_fingerprint": @"short"};
  QON_CHECK([store contextFingerprintForScope:userA] == nil,
            "a corrupt payload must read as no pin, never as a usable one");
  storage.objects[key] = @{@"schema_version": @2, @"scope_key": key,
                           @"context_fingerprint": QONRCPubFingerprint};
  QON_CHECK([store contextFingerprintForScope:userA] == nil,
            "an unknown schema must read as no pin");
  storage.objects[key] = @{
    @"schema_version": @1,
    @"scope_key": [QONRemoteConfigV2ContextPinStore storageKeyForScope:userB],
    @"context_fingerprint": QONRCPubFingerprint,
  };
  QON_CHECK([store contextFingerprintForScope:userA] == nil,
            "a payload keyed to another scope must not answer this one");

  [store removeContextFingerprintForScope:userA];
  QON_CHECK([store contextFingerprintForScope:userA] == nil, "removing a pin must clear it");
  storage.failWrites = YES;
  QON_CHECK(![store storeContextFingerprint:QONRCPubFingerprint forScope:userA],
            "a write that does not read back must be reported as a failure");
}

static void TestFirstAdmissionPinsTheContextAndLaterMismatchesAreRefused(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the context-pin scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1,
                              AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  QONRemoteConfigFetchResult *pinned = RunFetch(environment, 0, YES, NULL);
  QON_CHECK(pinned.status == QONRemoteConfigFetchStatusFetched && pinned.changed,
            "the first envelope of a scope must be admitted and pin its context");

  NSData *foreign = QONRCPubSnapshotBodyWithFingerprint(
      @"release-2", 2, AlphaValues(@"\"server-alpha-2\"", @"variation-a2"),
      QONRCPubOtherFingerprint);
  [environment.transport enqueueBody:foreign strongETag:QONRCPubStrongETag(foreign)];
  QONRemoteConfigFetchResult *refused = RunFetch(environment, 0, YES, NULL);
  QON_CHECK(!refused.changed && !refused.hasPendingActivation,
            "an envelope resolved for another client context must be refused");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-1"],
            "a refused envelope must not replace the pinned context's release");

  NSData *third = ReleaseBody(@"release-3", 3,
                              AlphaValues(@"\"server-alpha-3\"", @"variation-a3"));
  [environment.transport enqueueBody:third strongETag:QONRCPubStrongETag(third)];
  QONRemoteConfigFetchResult *readmitted = RunFetch(environment, 0, YES, NULL);
  QON_CHECK(readmitted.changed &&
                [[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-3"],
            "the pinned context must keep admitting its own envelopes");
}

// The coordinator always states an unpinned expectation, but the admission API
// still accepts a stated fingerprint. It must narrow the pin, never replace it.
static void TestAStatedFingerprintNarrowsThePinAndNeverReplacesIt(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the stated-fingerprint scenario");
  NSData *first = ReleaseBody(@"release-1", 1,
                              AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  QON_CHECK(RunFetch(environment, 0, YES, NULL).changed, "the scope must be pinned first");

  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = PinScope(@"user-a");
  NSData *body = ReleaseBody(@"release-2", 2, AlphaValues(@"\"server-alpha-2\"", @"variation-a2"));
  NSString *eTag = QONRCPubStrongETag(body);

  QONRemoteConfigV2AdmissionToken *conflicting = [manager beginAdmissionForScope:scope
      expectation:[[QONRemoteConfigV2EnvelopeExpectation alloc]
          initWithProjectID:QONRCPubProjectID
             environmentUID:QONRCPubEnvironmentUID
         contextFingerprint:QONRCPubOtherFingerprint]];
  QON_CHECK([manager admitBody:body strongETag:eTag admissionToken:conflicting] ==
                QONRemoteConfigV2TransitionStatusRejected,
            "a stated fingerprint that contradicts the pin must be refused");

  QONRemoteConfigV2AdmissionToken *agreeing = [manager beginAdmissionForScope:scope
      expectation:[[QONRemoteConfigV2EnvelopeExpectation alloc]
          initWithProjectID:QONRCPubProjectID
             environmentUID:QONRCPubEnvironmentUID
         contextFingerprint:QONRCPubFingerprint]];
  QON_CHECK([manager admitBody:body strongETag:eTag admissionToken:agreeing] ==
                QONRemoteConfigV2TransitionStatusAccepted,
            "a stated fingerprint that agrees with the pin must still admit");
}

/** An unpinned expectation: the shape the coordinator always states. */
static QONRemoteConfigV2EnvelopeExpectation *UnpinnedExpectation(void) {
  return [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:QONRCPubProjectID environmentUID:QONRCPubEnvironmentUID];
}

// Validation is not admission. A single replayed response from another client
// context, dropped by the release floor, must leave the scope unpinned —
// otherwise it would lock that install out of every later release, forever.
static void TestAnEnvelopeTheFloorDropsMustNotPinTheScope(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the rejected-envelope scenario");
  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = PinScope(@"user-a");

  // A locally built release carries no fingerprint, so the scope ends up with a
  // release floor while still being genuinely unpinned.
  QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"alpha"
          rawData:QONRCPubUTF8(@"\"seed\"")
     variationUID:@"variation-seed"
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate
         metadata:nil];
  QONRemoteConfigV2Release *seed = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"seed" releaseNumber:10 manifestContentHash:QONRCPubManifestHash
                 entries:@{@"alpha": entry}];
  QON_CHECK(entry != nil && seed != nil, "the locally built seed release must build");
  [manager acceptFetchedRelease:seed forScope:scope];
  QON_CHECK([manager activate], "the seed release must activate");

  NSData *foreign = QONRCPubSnapshotBodyWithFingerprint(
      @"release-3", 3, AlphaValues(@"\"server-alpha-3\"", @"variation-a3"),
      QONRCPubOtherFingerprint);
  QONRemoteConfigV2AdmissionToken *dropped =
      [manager beginAdmissionForScope:scope expectation:UnpinnedExpectation()];
  QON_CHECK([manager admitBody:foreign strongETag:QONRCPubStrongETag(foreign)
                admissionToken:dropped] == QONRemoteConfigV2TransitionStatusRejected,
            "an envelope below the release floor must be rejected");

  NSData *legitimate = ReleaseBody(@"release-11", 11,
                                   AlphaValues(@"\"server-alpha-11\"", @"variation-a11"));
  QONRemoteConfigV2AdmissionToken *next =
      [manager beginAdmissionForScope:scope expectation:UnpinnedExpectation()];
  QON_CHECK([manager admitBody:legitimate strongETag:QONRCPubStrongETag(legitimate)
                admissionToken:next] == QONRemoteConfigV2TransitionStatusAccepted,
            "a rejected envelope must not lock the scope out of its later releases");
}

// A device that cannot persist the pin must not admit what it cannot verify.
static void TestAnUnpinnableScopeFailsClosedInsteadOfAdmitting(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  environment.contextPinStore = [QONRCPubUnpinnableStore new];
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install over an unpinnable device");
  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = PinScope(@"user-a");

  NSData *body = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  QONRemoteConfigV2AdmissionToken *token =
      [manager beginAdmissionForScope:scope expectation:UnpinnedExpectation()];
  QON_CHECK([manager admitBody:body strongETag:QONRCPubStrongETag(body)
                admissionToken:token] ==
                QONRemoteConfigV2TransitionStatusPersistenceFailed,
            "a scope whose pin cannot be persisted must fail closed");
  QON_CHECK([environment.controller rawValueForKey:@"alpha"].source ==
                QONRemoteConfigValueSourceFallback,
            "nothing may be published when the pin could not be written");
}

static void TestTheContextPinSurvivesAStoreRecreation(void) {
  QONRCPubEnvironment *first = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(first, QONRemoteConfigV2ReadGuardBuildModeDebug, 0, @"user-a"),
            "the first run must install its engine");
  NSData *body = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [first.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
  QON_CHECK(RunFetch(first, 0, YES, NULL).changed,
            "the first run must pin its context");

  // A restart: same persistent storage, brand new stores, manager and engine.
  QONRCPubEnvironment *restarted = QONRCPubDormantEnvironment(DefaultsFixture());
  restarted.storage = first.storage;
  QON_CHECK(QONRCPubInstallEngine(restarted, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the restarted run must install over the surviving storage");
  QON_CHECK(restarted.contextPinStore != first.contextPinStore,
            "the restarted run must read the pin back rather than reuse the object");

  NSData *foreign = QONRCPubSnapshotBodyWithFingerprint(
      @"release-4", 4, AlphaValues(@"\"server-alpha-4\"", @"variation-a4"),
      QONRCPubOtherFingerprint);
  [restarted.transport enqueueBody:foreign strongETag:QONRCPubStrongETag(foreign)];
  QON_CHECK(!RunFetch(restarted, 0, YES, NULL).changed,
            "a restart must not be able to re-pin an unchanged scope");

  NSData *own = ReleaseBody(@"release-5", 5, AlphaValues(@"\"server-alpha-5\"", @"variation-a5"));
  [restarted.transport enqueueBody:own strongETag:QONRCPubStrongETag(own)];
  QON_CHECK(RunFetch(restarted, 0, YES, NULL).changed &&
                [[restarted.controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-5"],
            "the surviving pin must still admit the pinned context's own envelopes");
}

// An install that predates the pin store — or whose pin write never landed —
// already has a release on disk that was admitted under some fingerprint. That
// is the scope's real first use, so the next response must not be free to
// re-pin it to any context at all.
static void TestPersistedStateAnswersForAMissingPin(void) {
  QONRCPubEnvironment *first = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(first, QONRemoteConfigV2ReadGuardBuildModeDebug, 0, @"user-a"),
            "the first run must install its engine");
  NSData *body = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [first.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
  QON_CHECK(RunFetch(first, 0, YES, NULL).changed, "the first run must persist a release");

  QONRCPubEnvironment *restarted = QONRCPubDormantEnvironment(DefaultsFixture());
  restarted.storage = first.storage;
  // Everything the release left behind survives except the pin itself.
  [restarted.storage removeObjectForKey:
      [QONRemoteConfigV2ContextPinStore storageKeyForScope:PinScope(@"user-a")]];
  QON_CHECK(QONRCPubInstallEngine(restarted, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the restarted run must install over the surviving state");

  NSData *foreign = QONRCPubSnapshotBodyWithFingerprint(
      @"release-4", 4, AlphaValues(@"\"server-alpha-4\"", @"variation-a4"),
      QONRCPubOtherFingerprint);
  [restarted.transport enqueueBody:foreign strongETag:QONRCPubStrongETag(foreign)];
  QON_CHECK(!RunFetch(restarted, 0, YES, NULL).changed,
            "a release already on disk must answer for a pin the store has lost");

  NSData *own = ReleaseBody(@"release-5", 5, AlphaValues(@"\"server-alpha-5\"", @"variation-a5"));
  [restarted.transport enqueueBody:own strongETag:QONRCPubStrongETag(own)];
  QON_CHECK(RunFetch(restarted, 0, YES, NULL).changed,
            "the fingerprint the state was admitted under must still be admissible");
}

static void TestScopeResetClearsThePinAndTheNewIdentityRePins(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the scope-reset scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1,
                              AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  QON_CHECK(RunFetch(environment, 0, YES, NULL).changed, "user-a must pin its context");

  // A new identity is a new client context, so its fingerprint differs and the
  // forced fetch of the rebind must be free to pin it.
  NSData *foreign = QONRCPubSnapshotBodyWithFingerprint(
      @"release-2", 2, AlphaValues(@"\"server-alpha-b\"", @"variation-b1"),
      QONRCPubOtherFingerprint);
  [environment.transport enqueueBody:foreign strongETag:QONRCPubStrongETag(foreign)];
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  QON_CHECK(controller.activate, "the new identity's release must activate");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-b"],
            "an identity change must clear the pin so the new scope can pin its own");

  environment.clock.now += 10000;
  NSData *retired = ReleaseBody(@"release-3", 3,
                                AlphaValues(@"\"server-alpha-c\"", @"variation-c1"));
  [environment.transport enqueueBody:retired strongETag:QONRCPubStrongETag(retired)];
  QON_CHECK(!RunFetch(environment, 0, YES, NULL).changed,
            "the new identity must refuse the retired identity's context");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-b"],
            "a refused envelope must not disturb the new identity's release");

  // Returning to the first identity restores that identity's own pin, so the
  // fingerprint the second identity was pinned to is now the foreign one.
  NSData *foreignAgain = QONRCPubSnapshotBodyWithFingerprint(
      @"release-6", 6, AlphaValues(@"\"server-alpha-d\"", @"variation-d1"),
      QONRCPubOtherFingerprint);
  [environment.transport enqueueBody:foreignAgain strongETag:QONRCPubStrongETag(foreignAgain)];
  [controller switchToCanonicalUserID:@"user-a"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  [controller activate];
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-1"],
            "coming back to a pinned identity must restore its pin, not re-pin it");
}

// The controller never touches the install date itself: the transport owns it.
// This pins the device-scoped storage contract the identity switch relies on.
static void TestDeviceInstallDateIsDeviceScopedAcrossIdentities(void) {
  QONRCPubStorage *storage = [QONRCPubStorage new];
  QONRCPubClock *clock = [QONRCPubClock new];
  clock.now = 1700000000000;
  QONRemoteConfigV2DeviceInstallDateProvider *provider =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc]
          initWithLocalStorage:storage systemInstallDateSeconds:@(1500000000) clock:clock];
  NSNumber *first = [provider deviceInstalledAtSeconds];
  QON_CHECK([first isEqualToNumber:@(1500000000)],
            "the device install date must seed from the platform fact");
  QON_CHECK(storage.objects[QONRemoteConfigV2DeviceInstallDateStorageKey] != nil,
            "the device install date must live under one unscoped key");

  // A logout mints a brand-new anonymous identity; a provider rebuilt after it
  // must still report the original device fact.
  QONRemoteConfigV2DeviceInstallDateProvider *afterLogout =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc]
          initWithLocalStorage:storage systemInstallDateSeconds:@(1690000000) clock:clock];
  QON_CHECK([[afterLogout deviceInstalledAtSeconds] isEqualToNumber:first],
            "a logout must not rebind the device install date to the new identity");
}

static void TestReleaseBuildActivatesOnceSilentlyOnAFirstRead(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeRelease, 0,
                                  @"user-a"),
            "the engine must install in release mode");
  QONRemoteConfigController *controller = environment.controller;

  NSData *body = ReleaseBody(@"release-1", 1, [NSString stringWithFormat:@"\"alpha\":%@",
      QONRCPubItem(@"\"server-alpha-1\"", @"variation-a1", @"on_next_activate", @"null")]);
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, NO, NULL);
  QON_CHECK(result.hasPendingActivation,
            "the fetched release must be pending before any read");

  __block QONRemoteConfigFetchResult *timedOut = nil;
  environment.transport.holdNextRequest = YES;
  [controller fetchWithTimeout:0.05 completion:^(QONRemoteConfigFetchResult *result) {
    timedOut = result;
  }];
  [environment drain];
  QON_CHECK([environment.scheduler fireFirstPending], "the deadline must have been scheduled");
  [environment drain];
  QON_CHECK(timedOut.status == QONRemoteConfigFetchStatusTimedOut &&
                [timedOut.snapshot rawValueForKey:@"alpha"].source ==
                    QONRemoteConfigValueSourceFallback,
            "a timed-out call must report the active configuration, not a pending release");

  QONRemoteConfigValue *value = [controller rawValueForKey:@"alpha"];
  QON_CHECK(environment.readGuardAssertions == 0,
            "a release build must never raise the read-before-activate assertion");
  QON_CHECK(value.source == QONRemoteConfigValueSourceServer &&
                [value.value isEqual:@"server-alpha-1"],
            "a release build must silently activate the persisted release on the first read");
  QON_CHECK(!controller.activate,
            "the silent activation must consume the candidate exactly once");
}

static void TestTheRealAssemblyInstallsWithoutTouchingTheNetwork(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
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
  QON_CHECK(configured && controller.isConfigured,
            "the real assembly must build and install its engine");
  // Nothing is bound, so nothing may reach the network or the token storage.
  QON_CHECK(storage.objects.count == 0,
            "an unbindable assembly must not persist a session or a context pin");

  QON_CHECK(![controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                 projectToken:@"project-token"
                                   projectKey:QONRCPubProjectKey
                                  environment:QONRCPubEnvironmentUID
                              canonicalUserID:@"user-a"
                           readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                 localStorage:storage
                        clientContextProvider:[QONRCPubContextProvider new]
                                    projectID:0],
            "configuring twice must be refused");

  QONRemoteConfigValue *value = [controller rawValueForKey:@"alpha"];
  QON_CHECK(value.source == QONRemoteConfigValueSourceFallback,
            "an unbindable scope must still read its bundled defaults");
  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, NO, &deliveries);
  QON_CHECK(deliveries == 1 && result.status == QONRemoteConfigFetchStatusFailed,
            "a fetch on an unbound coordinator must fail rather than hang");
}

int main(void) {
  @autoreleasepool {
    TestDormantSurfaceServesBundledDefaultsAndRefusesToFetch();
    TestFetchStoresACandidateAndActivatePublishesItAtomically();
    TestSourceLadderWalksServerThenCacheThenFallback();
    TestTimeoutCompletesOnBestAvailableWhileTheRequestKeepsRunning();
    TestFetchAndActivatePublishesInOneCall();
    TestSubscribeReportsChangedKeysAndImmediateSwapsTheWholeRelease();
    TestASubscriptionMadeWhileDormantIsReplayedAfterConfiguration();
    TestIdentitySwitchDropsTheOldScopeImmediatelyAndForcesAFetch();
    TestASupersededIdentitySwitchCanNeverRebindItsScope();
    TestContextPinStoreIsScopeKeyedAndValidatesWhatItReadsBack();
    TestFirstAdmissionPinsTheContextAndLaterMismatchesAreRefused();
    TestAStatedFingerprintNarrowsThePinAndNeverReplacesIt();
    TestAnEnvelopeTheFloorDropsMustNotPinTheScope();
    TestAnUnpinnableScopeFailsClosedInsteadOfAdmitting();
    TestTheContextPinSurvivesAStoreRecreation();
    TestPersistedStateAnswersForAMissingPin();
    TestScopeResetClearsThePinAndTheNewIdentityRePins();
    TestDeviceInstallDateIsDeviceScopedAcrossIdentities();
    TestReleaseBuildActivatesOnceSilentlyOnAFirstRead();
    TestTheRealAssemblyInstallsWithoutTouchingTheNetwork();
  }
  if (failures == 0) {
    fprintf(stdout, "QONRemoteConfigControllerHarness: %lu/%lu passed\n",
            (unsigned long)checks, (unsigned long)checks);
  }
  return failures == 0 ? 0 : 1;
}
