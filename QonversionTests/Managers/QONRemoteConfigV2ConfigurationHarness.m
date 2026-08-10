//
//  Headless mirror of QONRemoteConfigV2ConfigurationTests.
//
//  XCTest needs a full Xcode install, so the public Remote Config configuration
//  is also runnable from the command line, exactly like the earlier slices:
//
//    clang -fobjc-arc -o /tmp/rc-config-harness \
//      QonversionTests/Managers/QONRemoteConfigV2ConfigurationHarness.m \
//      Sources/Qonversion/Public/QONRemoteConfigV2Configuration.m \
//      Sources/Qonversion/Public/QONConfiguration.m \
//      Sources/Qonversion/Qonversion/Constants/QNAPIConstants/QNAPIConstants.m \
//      $(find Sources -type d | sed 's/^/-I/') -framework Foundation
//
//  The `initWithConfig:` wiring group of the XCTest suite has no mirror here: it
//  needs the whole SDK object graph, which is exactly what a headless harness
//  cannot stand up.
//

#import <Foundation/Foundation.h>

#import "QNAPIConstants.h"
#import "QONConfiguration.h"
#import "QONRemoteConfigV2Configuration.h"
#import "QONRemoteConfigV2Configuration+Protected.h"

static NSUInteger failures = 0;
static NSUInteger checks = 0;
#define QON_CHECK(condition, message) do { checks += 1; if (!(condition)) { \
  failures += 1; fprintf(stderr, "FAIL: %s\n", message); } } while (0)

/** Runs `block` and reports whether it raised NSInvalidArgumentException. */
static BOOL RaisesInvalidArgument(void (^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return [exception.name isEqualToString:NSInvalidArgumentException];
  }
  return NO;
}

/** A string of `count` code points, each one outside the BMP. */
static NSString *AstralStringOfCodePoints(NSUInteger count) {
  NSMutableString *value = [NSMutableString new];
  for (NSUInteger index = 0; index < count; index++) {
    [value appendString:@"😀"];
  }
  return value;
}

#pragma mark - Tests

static void TestTheProductionInitializerAddressesTheProductionGateway(void) {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];

  QON_CHECK([configuration.baseURL isEqualToString:kRemoteConfigV2APIBase],
            "the production initializer must address the production gateway");
  QON_CHECK([configuration.baseURL isEqualToString:@"https://api2.qonversion.io/"],
            "the production gateway must be the production host");
  QON_CHECK([configuration.environmentUid isEqualToString:@"env-uid"],
            "the environment uid must be kept verbatim");
  QON_CHECK(configuration.minimumFetchIntervalMilliseconds == 0,
            "the minimum fetch interval must default to automatic");
}

static void TestAnExplicitGatewayIsKeptVerbatim(void) {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithBaseURL:@"http://localhost:8080/gateway"
                                               environmentUid:@"env-uid"];

  // No trailing slash is added and no path is dropped: the transport composes
  // the route on top of whatever prefix the caller stated.
  QON_CHECK([configuration.baseURL isEqualToString:@"http://localhost:8080/gateway"],
            "an explicit gateway must be kept verbatim");
}

static void TestEveryAbsoluteHTTPURLIsAccepted(void) {
  NSArray<NSString *> *accepted = @[
    @"https://gateway.example.com/",
    @"https://gateway.example.com",
    @"http://gateway.example.com/",
    @"https://gateway.example.com:8443/prefix/",
    @"https://user:pass@gateway.example.com/",
  ];

  for (NSString *baseURL in accepted) {
    QON_CHECK(!RaisesInvalidArgument(^{
      (void)[[QONRemoteConfigV2Configuration alloc] initWithBaseURL:baseURL
                                                    environmentUid:@"env-uid"];
    }), "an absolute http(s) url must be accepted");
  }
}

static void TestEveryMalformedBaseURLIsRefused(void) {
  NSArray<NSString *> *refused = @[
    @"gateway.example.com",          // relative
    @"//gateway.example.com",        // scheme-less
    @"ftp://gateway.example.com/",   // wrong scheme
    @"HTTPS://gateway.example.com/", // the scheme check is case sensitive
    @"https://",                     // a scheme and nothing to address
    @"http://",
    @"",
    @" https://gateway.example.com/", // leading space, so no scheme prefix
  ];

  for (NSString *baseURL in refused) {
    QON_CHECK(RaisesInvalidArgument(^{
      (void)[[QONRemoteConfigV2Configuration alloc] initWithBaseURL:baseURL
                                                    environmentUid:@"env-uid"];
    }), "a malformed base url must be refused");
  }

  QON_CHECK(RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc] initWithBaseURL:(NSString *_Nonnull)nil
                                                  environmentUid:@"env-uid"];
  }), "a nil base url must be refused");
}

static void TestTheEnvironmentUidLengthEdgesAreCountedInCodePoints(void) {
  QON_CHECK(!RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"e"];
  }), "a one code point environment uid must be accepted");

  QON_CHECK(!RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc]
        initWithEnvironmentUid:[@"" stringByPaddingToLength:36 withString:@"e" startingAtIndex:0]];
  }), "a thirty-six code point environment uid must be accepted");

  QON_CHECK(RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc]
        initWithEnvironmentUid:[@"" stringByPaddingToLength:37 withString:@"e" startingAtIndex:0]];
  }), "a thirty-seven code point environment uid must be refused");
}

static void TestAMultiByteEnvironmentUidIsMeasuredInCodePointsNotUnits(void) {
  // 36 astral code points are 72 UTF-16 units and 144 UTF-8 bytes. Counting
  // either of those would refuse a uid the gateway accepts.
  NSString *thirtySix = AstralStringOfCodePoints(36);
  QON_CHECK(thirtySix.length == 72,
            "the fixture must actually be a surrogate-pair string");
  QON_CHECK(!RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:thirtySix];
  }), "thirty-six astral code points must be accepted");

  QON_CHECK(RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc]
        initWithEnvironmentUid:AstralStringOfCodePoints(37)];
  }), "thirty-seven astral code points must be refused");
}

static void TestAnEmptyOrNilEnvironmentUidIsRefused(void) {
  QON_CHECK(RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@""];
  }), "an empty environment uid must be refused");

  QON_CHECK(RaisesInvalidArgument(^{
    (void)[[QONRemoteConfigV2Configuration alloc]
        initWithEnvironmentUid:(NSString *_Nonnull)nil];
  }), "a nil environment uid must be refused");
}

static void TestTheMinimumFetchIntervalDefaultsToAutomaticAndRefusesNegatives(void) {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];

  QON_CHECK(configuration.minimumFetchIntervalMilliseconds == 0,
            "the minimum fetch interval must default to automatic");

  [configuration setMinimumFetchIntervalMilliseconds:5000];
  QON_CHECK(configuration.minimumFetchIntervalMilliseconds == 5000,
            "a stated minimum fetch interval must be kept");

  QON_CHECK(RaisesInvalidArgument(^{
    [configuration setMinimumFetchIntervalMilliseconds:-1];
  }), "a negative minimum fetch interval must be refused");
  QON_CHECK(configuration.minimumFetchIntervalMilliseconds == 5000,
            "a refused interval must leave the previous one in place");
}

static void TestAnAutomaticIntervalMeansNoThrottleInDebugAndTheBuiltInOneInRelease(void) {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];

  QON_CHECK([[configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                  QONRemoteConfigV2ReadGuardBuildModeDebug] isEqualToNumber:@0],
            "a debug build must resolve an automatic interval to no throttle at all");
  QON_CHECK([configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                 QONRemoteConfigV2ReadGuardBuildModeRelease] == nil,
            "a release build must leave the built-in interval in place");
}

static void TestAStatedIntervalWinsInEveryBuildMode(void) {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];
  [configuration setMinimumFetchIntervalMilliseconds:1234];

  QON_CHECK([[configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                  QONRemoteConfigV2ReadGuardBuildModeDebug] isEqualToNumber:@1234],
            "a stated interval must win in a debug build");
  QON_CHECK([[configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                  QONRemoteConfigV2ReadGuardBuildModeRelease] isEqualToNumber:@1234],
            "a stated interval must win in a release build");
}

static void TestACopyCarriesEveryField(void) {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithBaseURL:@"https://gateway.example.com/"
                                               environmentUid:@"env-uid"];
  [configuration setMinimumFetchIntervalMilliseconds:7000];

  QONRemoteConfigV2Configuration *copy = [configuration copy];

  QON_CHECK(copy != configuration, "a copy must be its own object");
  QON_CHECK([copy.baseURL isEqualToString:@"https://gateway.example.com/"],
            "a copy must carry the base url");
  QON_CHECK([copy.environmentUid isEqualToString:@"env-uid"],
            "a copy must carry the environment uid");
  QON_CHECK(copy.minimumFetchIntervalMilliseconds == 7000,
            "a copy must carry the minimum fetch interval");

  [copy setMinimumFetchIntervalMilliseconds:1];
  QON_CHECK(configuration.minimumFetchIntervalMilliseconds == 7000,
            "changing a copy must not reach the original");
}

static void TestTheSDKConfigurationLeavesTheSurfaceOffByDefault(void) {
  QONConfiguration *configuration =
      [[QONConfiguration alloc] initWithProjectKey:@"project-key"
                                        launchMode:QONLaunchModeSubscriptionManagement];

  QONConfiguration *copy = [configuration copy];

  QON_CHECK(configuration.remoteConfigV2Configuration == nil,
            "the surface must be off unless the app asks for it");
  QON_CHECK(copy.remoteConfigV2Configuration == nil,
            "a copy of a dormant configuration must stay dormant");
}

static void TestTheSDKConfigurationCopiesTheRemoteConfigConfiguration(void) {
  QONRemoteConfigV2Configuration *remoteConfigConfiguration =
      [[QONRemoteConfigV2Configuration alloc] initWithBaseURL:@"https://gateway.example.com/"
                                               environmentUid:@"env-uid"];
  [remoteConfigConfiguration setMinimumFetchIntervalMilliseconds:9000];

  QONConfiguration *configuration =
      [[QONConfiguration alloc] initWithProjectKey:@"project-key"
                                        launchMode:QONLaunchModeSubscriptionManagement];
  [configuration setRemoteConfigV2Configuration:remoteConfigConfiguration];

  // Held by value, so a caller that keeps mutating its own object cannot change
  // what the SDK was configured with.
  [remoteConfigConfiguration setMinimumFetchIntervalMilliseconds:1];
  QON_CHECK(configuration.remoteConfigV2Configuration.minimumFetchIntervalMilliseconds == 9000,
            "the SDK configuration must hold the remote config configuration by value");

  QONConfiguration *copy = [configuration copy];
  QON_CHECK([copy.remoteConfigV2Configuration.baseURL isEqualToString:@"https://gateway.example.com/"],
            "a copy must carry the base url");
  QON_CHECK([copy.remoteConfigV2Configuration.environmentUid isEqualToString:@"env-uid"],
            "a copy must carry the environment uid");
  QON_CHECK(copy.remoteConfigV2Configuration.minimumFetchIntervalMilliseconds == 9000,
            "a copy must carry the minimum fetch interval");

  [configuration setRemoteConfigV2Configuration:nil];
  QON_CHECK(configuration.remoteConfigV2Configuration == nil,
            "the surface must be switchable back off");
}

static void TestTheGetterHandsOutACopySoNobodyCanReconfigureTheSDKThroughIt(void) {
  QONRemoteConfigV2Configuration *remoteConfigConfiguration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];
  [remoteConfigConfiguration setMinimumFetchIntervalMilliseconds:9000];

  QONConfiguration *configuration =
      [[QONConfiguration alloc] initWithProjectKey:@"project-key"
                                        launchMode:QONLaunchModeSubscriptionManagement];
  [configuration setRemoteConfigV2Configuration:remoteConfigConfiguration];

  // The object is mutable, so a getter that handed out the stored one would be
  // a setter nobody declared.
  [configuration.remoteConfigV2Configuration setMinimumFetchIntervalMilliseconds:1];

  QON_CHECK(configuration.remoteConfigV2Configuration.minimumFetchIntervalMilliseconds == 9000,
            "mutating what the getter returned must not reconfigure the SDK");
  QON_CHECK(configuration.remoteConfigV2Configuration !=
                configuration.remoteConfigV2Configuration,
            "every read must hand out its own copy");
}

int main(void) {
  @autoreleasepool {
    TestTheProductionInitializerAddressesTheProductionGateway();
    TestAnExplicitGatewayIsKeptVerbatim();
    TestEveryAbsoluteHTTPURLIsAccepted();
    TestEveryMalformedBaseURLIsRefused();
    TestTheEnvironmentUidLengthEdgesAreCountedInCodePoints();
    TestAMultiByteEnvironmentUidIsMeasuredInCodePointsNotUnits();
    TestAnEmptyOrNilEnvironmentUidIsRefused();
    TestTheMinimumFetchIntervalDefaultsToAutomaticAndRefusesNegatives();
    TestAnAutomaticIntervalMeansNoThrottleInDebugAndTheBuiltInOneInRelease();
    TestAStatedIntervalWinsInEveryBuildMode();
    TestACopyCarriesEveryField();
    TestTheSDKConfigurationLeavesTheSurfaceOffByDefault();
    TestTheSDKConfigurationCopiesTheRemoteConfigConfiguration();
    TestTheGetterHandsOutACopySoNobodyCanReconfigureTheSDKThroughIt();
  }
  if (failures == 0) {
    fprintf(stdout, "QONRemoteConfigV2ConfigurationHarness: %lu/%lu passed\n",
            (unsigned long)checks, (unsigned long)checks);
  }
  return failures == 0 ? 0 : 1;
}
