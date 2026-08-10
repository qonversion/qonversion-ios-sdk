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

#pragma mark - Context fingerprint
//
// The fingerprint hashes mutable targeting context (app/OS version, locale,
// purchases, properties); it rotates legitimately and MUST NOT be pinned
// across fetches. Identity isolation is the session's job. These tests hold
// the client to exactly that: shape in, no cross-response comparison, and
// isolation carried by the scoped storage keys.

static QONRemoteConfigV2Scope *ScopeForUser(NSString *canonicalUserID) {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:QONRCPubProjectKey
                                                environment:QONRCPubEnvironmentUID
                                            canonicalUserID:canonicalUserID];
}

/** The expectation the admission path always builds: no fingerprint at all. */
static QONRemoteConfigV2EnvelopeExpectation *OpenExpectation(void) {
  return [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:QONRCPubProjectID environmentUID:QONRCPubEnvironmentUID];
}

static void TestAFingerprintRotationBetweenFetchesIsAdmitted(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the rotation scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *first = ReleaseBody(@"release-1", 1,
                              AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [environment.transport enqueueBody:first strongETag:QONRCPubStrongETag(first)];
  QON_CHECK(RunFetch(environment, 0, YES, NULL).changed,
            "the first response must be admitted");

  // An app update, a locale change, a purchase or a property write is enough to
  // move the fingerprint. The same user, the same scope, a different tag.
  NSData *rotated = QONRCPubSnapshotBodyWithFingerprint(
      @"release-2", 2, AlphaValues(@"\"server-alpha-2\"", @"variation-a2"),
      QONRCPubOtherFingerprint);
  [environment.transport enqueueBody:rotated strongETag:QONRCPubStrongETag(rotated)];
  QON_CHECK(RunFetch(environment, 0, YES, NULL).changed,
            "a rotated fingerprint must be admitted, not refused");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-2"],
            "the rotated response must publish its own values");

  // And back again: the tag carries no ordering and no history.
  NSData *rotatedBack = ReleaseBody(@"release-3", 3,
                                    AlphaValues(@"\"server-alpha-3\"", @"variation-a3"));
  [environment.transport enqueueBody:rotatedBack strongETag:QONRCPubStrongETag(rotatedBack)];
  QON_CHECK(RunFetch(environment, 0, YES, NULL).changed &&
                [[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-3"],
            "rotating back to an earlier fingerprint must be admitted too");
}

static void TestAFingerprintRotationSurvivesARestart(void) {
  QONRCPubEnvironment *first = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(first, QONRemoteConfigV2ReadGuardBuildModeDebug, 0, @"user-a"),
            "the first run must install its engine");
  NSData *body = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  [first.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
  QON_CHECK(RunFetch(first, 0, YES, NULL).changed, "the first run must persist a release");

  // A restart is where an app update lands, so it is exactly where the
  // fingerprint is most likely to have moved. Nothing may refuse it.
  QONRCPubEnvironment *restarted = QONRCPubDormantEnvironment(DefaultsFixture());
  restarted.storage = first.storage;
  QON_CHECK(QONRCPubInstallEngine(restarted, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the restarted run must install over the surviving storage");
  NSData *rotated = QONRCPubSnapshotBodyWithFingerprint(
      @"release-4", 4, AlphaValues(@"\"server-alpha-4\"", @"variation-a4"),
      QONRCPubOtherFingerprint);
  [restarted.transport enqueueBody:rotated strongETag:QONRCPubStrongETag(rotated)];
  QON_CHECK(RunFetch(restarted, 0, YES, NULL).changed &&
                [[restarted.controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-4"],
            "a restart must admit a fingerprint the previous run never saw");
}

static void TestAMalformedContextFingerprintIsRefused(void) {
  QON_CHECK(QONRemoteConfigV2ValidContextFingerprint(QONRCPubFingerprint),
            "a lowercase 64-hex fingerprint must be well formed");
  QON_CHECK(!QONRemoteConfigV2ValidContextFingerprint(nil) &&
                !QONRemoteConfigV2ValidContextFingerprint(@"") &&
                !QONRemoteConfigV2ValidContextFingerprint(
                    [QONRCPubFingerprint substringToIndex:63]) &&
                !QONRemoteConfigV2ValidContextFingerprint(
                    [QONRCPubFingerprint stringByAppendingString:@"a"]) &&
                !QONRemoteConfigV2ValidContextFingerprint(QONRCPubFingerprint.uppercaseString) &&
                !QONRemoteConfigV2ValidContextFingerprint(
                    [@"g" stringByPaddingToLength:64 withString:@"g" startingAtIndex:0]),
            "wrong length, wrong case and non-hex must all be malformed");

  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the shape scenario");
  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = ScopeForUser(@"user-a");

  NSData *malformed = QONRCPubSnapshotBodyWithFingerprint(
      @"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"),
      QONRCPubFingerprint.uppercaseString);
  QONRemoteConfigV2AdmissionToken *bad = [manager beginAdmissionForScope:scope];
  QON_CHECK([manager admitBody:malformed strongETag:QONRCPubStrongETag(malformed)
                     projectID:QONRCPubProjectID
                admissionToken:bad] == QONRemoteConfigV2TransitionStatusRejected,
            "an envelope whose fingerprint is the wrong shape must be refused");
  QON_CHECK([environment.controller rawValueForKey:@"alpha"].source ==
                QONRemoteConfigValueSourceFallback,
            "a refused envelope must publish nothing");

  NSData *wellFormed = ReleaseBody(@"release-1", 1,
                                   AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  QONRemoteConfigV2AdmissionToken *good = [manager beginAdmissionForScope:scope];
  QON_CHECK([manager admitBody:wellFormed strongETag:QONRCPubStrongETag(wellFormed)
                     projectID:QONRCPubProjectID
                admissionToken:good] == QONRemoteConfigV2TransitionStatusAccepted,
            "the same envelope with a well-formed fingerprint must be admitted");
}

// The project id reaching admission is the one the gateway stated for the
// session these bytes came back on. It is the envelope boundary, so an envelope
// from another project is refused rather than published.
static void TestAnEnvelopeFromAnotherProjectIsRefused(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the project boundary scenario");
  QONRemoteConfigV2Manager *manager = environment.manager;
  QONRemoteConfigV2Scope *scope = ScopeForUser(@"user-a");
  NSData *body = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  NSString *eTag = QONRCPubStrongETag(body);

  QONRemoteConfigV2AdmissionToken *foreign = [manager beginAdmissionForScope:scope];
  QON_CHECK([manager admitBody:body strongETag:eTag
                     projectID:QONRCPubProjectID + 1
                admissionToken:foreign] == QONRemoteConfigV2TransitionStatusRejected,
            "an envelope whose project_id is not the learned one must be refused");
  QON_CHECK([environment.controller rawValueForKey:@"alpha"].source ==
                QONRemoteConfigValueSourceFallback,
            "a refused envelope must publish nothing");

  // Zero is not a project: it is what a response that learned nothing carries,
  // and it must never read as "no boundary to check".
  QONRemoteConfigV2AdmissionToken *unlearned = [manager beginAdmissionForScope:scope];
  QON_CHECK([manager admitBody:body strongETag:eTag projectID:0
                admissionToken:unlearned] == QONRemoteConfigV2TransitionStatusRejected,
            "an unstated project id must refuse the body, not admit it unconstrained");

  QONRemoteConfigV2AdmissionToken *learned = [manager beginAdmissionForScope:scope];
  QON_CHECK([manager admitBody:body strongETag:eTag projectID:QONRCPubProjectID
                admissionToken:learned] == QONRemoteConfigV2TransitionStatusAccepted,
            "the same bytes under the learned project id must be admitted");
}

// A stated fingerprint constrains that one parse and nothing beyond it. It is
// not a pin, and the admission path never states one: nothing on the device can
// predict the next tag, so the manager always parses against an open
// expectation. The constraint remains available to a caller that already holds
// the exact response it means to admit, which is the parser's contract.
static void TestAStatedFingerprintConstrainsOnlyItsOwnCall(void) {
  QONRemoteConfigV2EnvelopeParser *parser = [QONRemoteConfigV2EnvelopeParser new];
  NSData *body = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-1\"", @"variation-a1"));
  NSString *eTag = QONRCPubStrongETag(body);

  QONRemoteConfigV2EnvelopeExpectation *mismatched =
      [[QONRemoteConfigV2EnvelopeExpectation alloc]
          initWithProjectID:QONRCPubProjectID
             environmentUID:QONRCPubEnvironmentUID
         contextFingerprint:QONRCPubOtherFingerprint];
  QON_CHECK([parser parseBody:body strongETag:eTag expectation:mismatched] == nil,
            "an envelope that is not the response the caller named must be refused");

  QON_CHECK([parser parseBody:body strongETag:eTag expectation:OpenExpectation()] != nil,
            "the refusal must not outlive its own call");
}

static void TestScopeIsolationIsKeyedStorageNotTheFingerprint(void) {
  QONRemoteConfigV2Scope *userA = ScopeForUser(@"user-a");
  QONRemoteConfigV2Scope *userB = ScopeForUser(@"user-b");
  QON_CHECK(![[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:userA]
                isEqualToString:[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:userB]],
            "two identities must never share a session token key");

  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install for the isolation scenario");
  QONRemoteConfigController *controller = environment.controller;

  NSData *forA = ReleaseBody(@"release-1", 1, AlphaValues(@"\"server-alpha-a\"", @"variation-a1"));
  [environment.transport enqueueBody:forA strongETag:QONRCPubStrongETag(forA)];
  QON_CHECK(RunFetch(environment, 0, YES, NULL).changed, "the first identity must be served");

  // The second identity's response carries a different fingerprint, as it
  // would in production. Isolation comes from the scope, not from that.
  NSData *forB = QONRCPubSnapshotBodyWithFingerprint(
      @"release-2", 2, AlphaValues(@"\"server-alpha-b\"", @"variation-b1"),
      QONRCPubOtherFingerprint);
  [environment.transport enqueueBody:forB strongETag:QONRCPubStrongETag(forB)];
  [controller switchToCanonicalUserID:@"user-b"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  QON_CHECK(controller.activate, "the new identity's release must activate");
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-b"],
            "the second identity must read its own release");

  [controller switchToCanonicalUserID:@"user-a"
                               change:QONRemoteConfigControllerIdentityChangeIdentify];
  [environment settleIdentity];
  [controller activate];
  QON_CHECK([[controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-a"],
            "coming back must restore that identity's own release, keyed by scope");
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

  // No identity yet, so no scope to bind: the real assembly is exercised end to
  // end with no request ever leaving. Nothing here states a project id — the
  // SDK has none to state until the gateway bootstrap hands it one.
  BOOL configured = [controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                        projectToken:@"project-token"
                                          projectKey:QONRCPubProjectKey
                                         environment:QONRCPubEnvironmentUID
                                     canonicalUserID:nil
                                  readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                        localStorage:storage
                               clientContextProvider:[QONRCPubContextProvider new]];
  QON_CHECK(configured && controller.isConfigured,
            "the real assembly must build and install its engine");
  // Nothing is bound, so nothing may reach the network or the token storage.
  QON_CHECK(storage.objects.count == 0,
            "an unbound assembly must not persist a session or a project identity");

  QON_CHECK(![controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                 projectToken:@"project-token"
                                   projectKey:QONRCPubProjectKey
                                  environment:QONRCPubEnvironmentUID
                              canonicalUserID:nil
                           readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                 localStorage:storage
                        clientContextProvider:[QONRCPubContextProvider new]],
            "configuring twice must be refused");

  QONRemoteConfigValue *value = [controller rawValueForKey:@"alpha"];
  QON_CHECK(value.source == QONRemoteConfigValueSourceFallback,
            "an unbound scope must still read its bundled defaults");
  NSUInteger deliveries = 0;
  QONRemoteConfigFetchResult *result = RunFetch(environment, 0, NO, &deliveries);
  QON_CHECK(deliveries == 1 && result.status == QONRemoteConfigFetchStatusFailed,
            "a fetch on an unbound coordinator must fail rather than hang");
}

/** Runs the real assembly with a stated interval and reports what it installed. */
static int64_t InstalledIntervalForStatedInterval(NSNumber *_Nullable stated, BOOL *configured) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QONRemoteConfigController *controller = environment.controller;
  BOOL installed = [controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                       projectToken:@"project-token"
                                         projectKey:QONRCPubProjectKey
                                        environment:QONRCPubEnvironmentUID
                                    canonicalUserID:nil
                                 readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                       localStorage:[QONRCPubStorage new]
                              clientContextProvider:[QONRCPubContextProvider new]
                   minimumFetchIntervalMilliseconds:stated];
  if (configured) *configured = installed && controller.isConfigured;
  return controller.installedMinimumFetchIntervalMilliseconds;
}

static void TestAStatedMinimumFetchIntervalReachesTheFetchPolicy(void) {
  QONRCPubEnvironment *dormant = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(dormant.controller.installedMinimumFetchIntervalMilliseconds == -1,
            "a dormant surface must report no interval at all, not a zero one");

  BOOL configured = NO;
  QON_CHECK(InstalledIntervalForStatedInterval(@4242, &configured) == 4242,
            "a stated interval must reach the fetch policy");
  QON_CHECK(configured, "a stated interval must not stop the assembly from installing");

  // The built-in constant is a default, not a floor: a stated 0 means the app
  // asked for no throttle at all, which is what a debug build resolves to.
  QON_CHECK(InstalledIntervalForStatedInterval(@0, NULL) == 0,
            "a stated zero must disable the throttle outright");

  QON_CHECK(InstalledIntervalForStatedInterval(nil, NULL) == 60 * 60 * 1000,
            "an unstated interval must leave the SDK's built-in one in place");
}

static void TestANegativeMinimumFetchIntervalLeavesTheSurfaceDormant(void) {
  BOOL configured = YES;
  QON_CHECK(InstalledIntervalForStatedInterval(@(-1), &configured) == -1,
            "a refused assembly must install no interval");
  QON_CHECK(!configured, "a negative interval must be refused, exactly like the policy refuses it");
}

#pragma mark - Activation ack

/** The ack the fake gateway recorded at `index`, or nil. */
static QONRCPubRecordedAck *RecordedAck(QONRCPubEnvironment *environment, NSUInteger index) {
  [environment settleAcks];
  NSArray<QONRCPubRecordedAck *> *acks = nil;
  @synchronized (environment.ackTransport) {
    acks = [environment.ackTransport.acks copy];
  }
  return index < acks.count ? acks[index] : nil;
}

/** Walks the bounded retry ladder to its end without racing the timer it arms. */
static void RunAckRetryLadder(QONRCPubEnvironment *environment) {
  [environment settleAcks];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2ActivationAckMaximumAttempts; attempt++) {
    QON_CHECK([environment.ackScheduler fireFirstPending],
              "a retry must be scheduled after every failed ack attempt");
    [environment settleAcks];
  }
}

/** Fetches one release and returns its body. */
static void ServeRelease(QONRCPubEnvironment *environment, NSString *releaseUID,
                         NSInteger releaseNumber, NSString *rawValue) {
  NSData *body = ReleaseBody(releaseUID, releaseNumber,
                             AlphaValues(rawValue, @"variation-a1"));
  [environment.transport enqueueBody:body strongETag:QONRCPubStrongETag(body)];
  RunFetch(environment, 0, NO, NULL);
}

static void TestAnExplicitActivationIsAckedExactlyOnce(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install over the fake seams");
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");

  QON_CHECK(environment.controller.activate, "the fetched release must activate");
  QON_CHECK(environment.ackCount == 1, "an activation that changes the served release is acked");

  QONRCPubRecordedAck *ack = RecordedAck(environment, 0);
  QON_CHECK([ack.scope.canonicalUserID isEqualToString:@"user-a"],
            "the ack must name the identity that activated");
  QON_CHECK(ack.ack.releaseNumber == 1, "the ack must name the release that now serves");
  QON_CHECK(ack.ack.activatedAtSeconds > 0, "the ack must be stamped when it was activated");

  // Re-activating the same release owes nothing, however often it is asked for.
  [environment.controller activate];
  [environment.controller activate];
  QON_CHECK(environment.ackCount == 1, "a re-activation of an acked release costs no request");
}

static void TestActivatingANewerReleaseAcksItAndNeverReAcksTheOld(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install over the fake seams");
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");
  [environment.controller activate];
  QON_CHECK(environment.ackCount == 1, "the first release is acked");

  ServeRelease(environment, @"release-2", 2, @"\"server-alpha-2\"");
  QON_CHECK(environment.controller.activate, "the newer release must activate");
  QON_CHECK(environment.ackCount == 2, "the newer release is acked too");
  QON_CHECK(RecordedAck(environment, 0).ack.releaseNumber == 1 &&
                RecordedAck(environment, 1).ack.releaseNumber == 2,
            "each release is acked exactly once, in the order it started serving");
}

static void TestAnActivationNeverWaitsOnAHungAckEndpoint(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install over the fake seams");
  // The gateway accepts the ack and never answers it.
  environment.ackTransport.hang = YES;
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");

  // Would never return if the activation joined the ack in any way.
  QON_CHECK(environment.controller.activate, "an activation must never wait on the ack");
  QON_CHECK(environment.ackCount == 1, "the ack is on the wire");
  QON_CHECK([[environment.controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-1"],
            "and a read is not blocked by it either");

  // The wedged ack neither blocks nor re-arms anything.
  [environment.controller activate];
  QON_CHECK(environment.ackCount == 1,
            "a second activation of the same release stays silent while one is in flight");
}

static void TestAReadThatImplicitlyActivatesIsAcked(void) {
  // Release builds activate on the first read instead of asserting; that
  // activation changes the served release exactly as an explicit one does.
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeRelease, 0,
                                  @"user-a"),
            "the engine must install in release mode");
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");
  QON_CHECK(environment.ackCount == 0, "a fetch alone owes no ack");

  QON_CHECK([[environment.controller rawValueForKey:@"alpha"].value isEqual:@"server-alpha-1"],
            "the first read must activate silently");
  QON_CHECK(environment.readGuardAssertions == 0, "and never accuse the app");
  QON_CHECK(environment.ackCount == 1, "an implicit activation is acked exactly like an explicit one");
  QON_CHECK(RecordedAck(environment, 0).ack.releaseNumber == 1, "and names the same release");

  // The explicit activate() that follows reports unchanged and must not ack again.
  [environment.controller activate];
  QON_CHECK(environment.ackCount == 1, "the explicit activate that follows stays silent");
}

static void TestAnAckAProcessCouldNotDeliverIsDeliveredByTheNextOne(void) {
  QONRCPubEnvironment *crashed = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(crashed, QONRemoteConfigV2ReadGuardBuildModeDebug, 0, @"user-a"),
            "the first run must install");
  [crashed.ackTransport scriptResponse:QONRemoteConfigV2AckResponseRetryable
                                 times:QONRemoteConfigV2ActivationAckMaximumAttempts];
  ServeRelease(crashed, @"release-1", 1, @"\"server-alpha-1\"");
  [crashed.controller activate];
  RunAckRetryLadder(crashed);
  QON_CHECK(crashed.ackCount == (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "the first process walks the bounded ladder");
  QON_CHECK(crashed.ackSender.droppedAckCount == 1,
            "and abandons the ack for the rest of its life");

  // A new process over the same durable state.
  QONRCPubEnvironment *restarted = QONRCPubDormantEnvironment(DefaultsFixture());
  restarted.storage = crashed.storage;
  QON_CHECK(QONRCPubInstallEngine(restarted, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the restarted run must install over the surviving storage");
  [restarted settleAcks];

  QON_CHECK(restarted.ackCount == 1, "binding the identity resumes the ack the last process owed");
  QON_CHECK(RecordedAck(restarted, 0).ack.releaseNumber == 1, "and it still names release 1");
  QON_CHECK(restarted.ackSender.droppedAckCount == 0, "the new process drops nothing");
  // Nothing is owed any more, so a later activation of the same release is silent.
  [restarted.controller activate];
  QON_CHECK(restarted.ackCount == 1, "a settled release is never acked again");
}

static void TestIdentityChurnDoesNotReArmAnAbandonedAck(void) {
  // Every identity change unbinds and rebinds the ack queue. An app that
  // identifies on every foreground must not turn a failing /ack into a
  // permanent low-rate storm.
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0,
                                  @"user-a"),
            "the engine must install over the fake seams");
  [environment.ackTransport scriptResponse:QONRemoteConfigV2AckResponseRetryable
                                     times:QONRemoteConfigV2ActivationAckMaximumAttempts];
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");
  [environment.controller activate];
  RunAckRetryLadder(environment);
  QON_CHECK(environment.ackCount == (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "the ladder is walked to its bound");

  for (NSUInteger round = 0; round < 3; round++) {
    [environment.controller switchToCanonicalUserID:@"user-b"
                                             change:QONRemoteConfigControllerIdentityChangeIdentify];
    [environment settleIdentity];
    [environment.controller switchToCanonicalUserID:@"user-a"
                                             change:QONRemoteConfigControllerIdentityChangeIdentify];
    [environment settleIdentity];
  }

  QON_CHECK(environment.ackCount == (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "identity churn must never buy an abandoned ack another ladder");
  QON_CHECK(environment.ackSender.droppedAckCount == 1, "and must never re-count the drop");
}

static void TestAnSDKThatNeverLearnedAnIdentityAcksNothing(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeDebug, 0, nil),
            "the engine must install without an identity");

  [environment.controller activate];
  [environment.controller current];

  QON_CHECK(environment.ackCount == 0, "an SDK that never learned an identity acks nothing");

  // ...and neither does a surface that was never configured at all.
  QONRCPubEnvironment *dormant = QONRCPubDormantEnvironment(DefaultsFixture());
  [dormant.controller activate];
  [dormant.controller current];
  QON_CHECK(dormant.ackTransport == nil, "a dormant surface has no ack queue to speak through");
}

#pragma mark - Client telemetry

/** A telemetry environment: the same fakes, with the telemetry taps wired in. */
static QONRCPubEnvironment *TelemetryEnvironment(QONRemoteConfigV2ReadGuardBuildMode buildMode) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  environment.wantsTelemetry = YES;
  QON_CHECK(QONRCPubInstallEngine(environment, buildMode, 0, @"user-a"),
            "the engine must install with telemetry wired");
  return environment;
}

static QONRemoteConfigV2TelemetrySender *_Nullable LooseTelemetrySender(void) {
  return [[QONRemoteConfigV2TelemetrySender alloc]
      initWithTransport:[QONRCPubTelemetryTransport new]
                  store:[[QONRemoteConfigV2TelemetryStore alloc]
                            initWithLocalStorage:[QONRCPubStorage new]]
                  clock:[QONRCPubClock new]
                 random:[QONRCPubRandom new]
              scheduler:[QONRCPubScheduler new]
                  queue:dispatch_queue_create("io.qonversion.rc-pub-telemetry-loose",
                                              DISPATCH_QUEUE_SERIAL)];
}

static void TestADecodeFailureIsReportedWithoutChangingTheRead(void) {
  QONRCPubEnvironment *environment = TelemetryEnvironment(QONRemoteConfigV2ReadGuardBuildModeDebug);
  QONRemoteConfigController *controller = environment.controller;
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");
  QON_CHECK(controller.activate, "the first release must activate");
  ServeRelease(environment, @"release-2", 2, @"\"rejected-alpha\"");
  QON_CHECK(controller.activate, "the second release must activate");

  QONRemoteConfigValue *value = [controller valueForKey:@"alpha"
                                                decoder:QONRCPubPrefixDecoder(@"server-")];
  QON_CHECK(value.source == QONRemoteConfigValueSourceCache &&
                [value.value isEqual:@"server-alpha-1"],
            "telemetry must not change what a read returns");

  NSArray<QONRemoteConfigV2TelemetryEvent *> *events =
      [environment flushedTelemetryOfKind:QONRemoteConfigV2TelemetryKindDecodeFailure];
  QON_CHECK(events.count == 1, "a rejected served value must be reported exactly once");
  QON_CHECK([events.firstObject.logicalKey isEqualToString:@"alpha"],
            "with the key the app could not read");
  QON_CHECK(events.firstObject.releaseNumber == 2,
            "and the release that served it, not the one that saved the read");
  QON_CHECK(events.firstObject.count == 1, "one read, one occurrence");
}

static void TestRepeatedDecodeFailuresCoalesce(void) {
  QONRCPubEnvironment *environment = TelemetryEnvironment(QONRemoteConfigV2ReadGuardBuildModeDebug);
  QONRemoteConfigController *controller = environment.controller;
  ServeRelease(environment, @"release-1", 1, @"\"rejected-alpha\"");
  QON_CHECK(controller.activate, "the release must activate");

  for (NSUInteger index = 0; index < 200; index++) {
    QON_CHECK([controller valueForKey:@"alpha" decoder:QONRCPubPrefixDecoder(@"server-")] == nil,
              "every candidate is rejected, so every read resolves nowhere");
  }

  NSArray<QONRemoteConfigV2TelemetryEvent *> *events =
      [environment flushedTelemetryOfKind:QONRemoteConfigV2TelemetryKindDecodeFailure];
  QON_CHECK(events.count == 1, "two hundred failing reads must not become two hundred records");
  // Both the served value and the bundled default are rejected, and the served
  // one is the higher-priority rejection, so that is the one reported.
  QON_CHECK(events.firstObject.count == 200, "they are one counted event");
  QON_CHECK(environment.telemetrySender.droppedEventCount == 0, "and nothing was dropped");
}

static void TestReadGuardEventsReachTheTelemetryQueue(void) {
  QONRCPubEnvironment *environment =
      TelemetryEnvironment(QONRemoteConfigV2ReadGuardBuildModeRelease);
  ServeRelease(environment, @"release-1", 1, @"\"server-alpha-1\"");

  // A read before any activate: the release build activates silently and both
  // facts are worth reporting.
  QON_CHECK([environment.controller.current rawValueForKey:@"alpha"] != nil,
            "the read still returns the configuration");
  [environment settleTelemetry];

  NSArray<QONRemoteConfigV2TelemetryEvent *> *readBeforeActivate =
      [environment flushedTelemetryOfKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate];
  QON_CHECK(readBeforeActivate.count == 1, "a read before activate must be reported");
  QON_CHECK(readBeforeActivate.firstObject.logicalKey == nil,
            "a keyless kind must never state a key");
  QON_CHECK(readBeforeActivate.firstObject.releaseNumber == 0,
            "and must state an unknown release rather than re-enter the manager for one");
  QON_CHECK(environment.readGuardAssertions == 0,
            "and the release build must still not raise the assertion");
}

/**
 A fresh install has no persisted configuration to preload, and that is the
 normal state — not a failure. Reporting it would fire preload_failed once for
 every new user and bury the genuine failures under them.
 */
static void TestAFreshInstallNeverReportsAPreloadFailure(void) {
  QONRCPubEnvironment *environment =
      TelemetryEnvironment(QONRemoteConfigV2ReadGuardBuildModeRelease);
  // Nothing was ever served, so binding the identity found nothing to preload.
  QON_CHECK([environment.controller.current rawValueForKey:@"alpha"] != nil,
            "the read still resolves from the bundled defaults");

  QON_CHECK([environment flushedTelemetryOfKind:QONRemoteConfigV2TelemetryKindPreloadFailed]
                .count == 0,
            "an absent preload is the normal first-launch state, not a failure");
  QON_CHECK([environment flushedTelemetryOfKind:QONRemoteConfigV2TelemetryKindPreloadCorrupt]
                .count == 0,
            "and nothing was corrupt either");
}

static void TestASurfaceWithoutATelemetryQueueStaysSilent(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK(QONRCPubInstallEngine(environment, QONRemoteConfigV2ReadGuardBuildModeRelease, 0,
                                  @"user-a"),
            "the engine must install without telemetry");
  QON_CHECK(environment.telemetrySender == nil, "and must install no telemetry queue");

  ServeRelease(environment, @"release-1", 1, @"\"rejected-alpha\"");
  QON_CHECK(environment.controller.activate, "the release must activate");
  QON_CHECK([environment.controller valueForKey:@"alpha"
                                        decoder:QONRCPubPrefixDecoder(@"server-")] == nil,
            "a decode failure with nowhere to report must behave exactly as before");
  QON_CHECK([environment.controller.current rawValueForKey:@"alpha"] != nil,
            "and so must every other read");
}

static void TestTheTelemetryQueueIsInstalledExactlyOnce(void) {
  QONRCPubEnvironment *environment = TelemetryEnvironment(QONRemoteConfigV2ReadGuardBuildModeDebug);
  QON_CHECK(![environment.controller installTelemetrySender:LooseTelemetrySender()],
            "a second telemetry queue must be refused");

  QONRCPubEnvironment *dormant = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK([dormant.controller installTelemetrySender:LooseTelemetrySender()],
            "and a controller that has none must accept one");
}

static void TestTheRealAssemblyInstallsTheTelemetryQueue(void) {
  QONRCPubEnvironment *environment = QONRCPubDormantEnvironment(DefaultsFixture());
  QONRemoteConfigController *controller = environment.controller;
  QON_CHECK([controller configureWithBaseURL:[NSURL URLWithString:@"https://gateway.invalid/"]
                                projectToken:@"project-token"
                                  projectKey:QONRCPubProjectKey
                                 environment:QONRCPubEnvironmentUID
                             canonicalUserID:nil
                          readGuardBuildMode:QONRemoteConfigV2ReadGuardBuildModeDebug
                                localStorage:[QONRCPubStorage new]
                       clientContextProvider:[QONRCPubContextProvider new]],
            "the real assembly must build and install its engine");
  // The only way to observe the queue from outside is that the slot is taken.
  QON_CHECK(![controller installTelemetrySender:LooseTelemetrySender()],
            "the shipped assembly must have installed a telemetry queue of its own");

  QONRCPubEnvironment *dormant = QONRCPubDormantEnvironment(DefaultsFixture());
  QON_CHECK([dormant.controller installTelemetrySender:LooseTelemetrySender()],
            "while a surface nobody configured stays dormant, with no queue at all");
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
    TestAFingerprintRotationBetweenFetchesIsAdmitted();
    TestAFingerprintRotationSurvivesARestart();
    TestAMalformedContextFingerprintIsRefused();
    TestAStatedFingerprintConstrainsOnlyItsOwnCall();
    TestAnEnvelopeFromAnotherProjectIsRefused();
    TestScopeIsolationIsKeyedStorageNotTheFingerprint();
    TestDeviceInstallDateIsDeviceScopedAcrossIdentities();
    TestReleaseBuildActivatesOnceSilentlyOnAFirstRead();
    TestTheRealAssemblyInstallsWithoutTouchingTheNetwork();
    TestAStatedMinimumFetchIntervalReachesTheFetchPolicy();
    TestANegativeMinimumFetchIntervalLeavesTheSurfaceDormant();

    TestAnExplicitActivationIsAckedExactlyOnce();
    TestActivatingANewerReleaseAcksItAndNeverReAcksTheOld();
    TestAnActivationNeverWaitsOnAHungAckEndpoint();
    TestAReadThatImplicitlyActivatesIsAcked();
    TestAnAckAProcessCouldNotDeliverIsDeliveredByTheNextOne();
    TestIdentityChurnDoesNotReArmAnAbandonedAck();
    TestAnSDKThatNeverLearnedAnIdentityAcksNothing();

    TestADecodeFailureIsReportedWithoutChangingTheRead();
    TestRepeatedDecodeFailuresCoalesce();
    TestReadGuardEventsReachTheTelemetryQueue();
    TestAFreshInstallNeverReportsAPreloadFailure();
    TestASurfaceWithoutATelemetryQueueStaysSilent();
    TestTheTelemetryQueueIsInstalledExactlyOnce();
    TestTheRealAssemblyInstallsTheTelemetryQueue();
  }
  if (failures == 0) {
    fprintf(stdout, "QONRemoteConfigControllerHarness: %lu/%lu passed\n",
            (unsigned long)checks, (unsigned long)checks);
  }
  return failures == 0 ? 0 : 1;
}
