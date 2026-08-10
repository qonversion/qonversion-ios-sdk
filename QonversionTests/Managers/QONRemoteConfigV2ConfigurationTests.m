//
//  QONRemoteConfigV2ConfigurationTests.m
//  QonversionTests
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//
//  The headless mirror of this suite is QONRemoteConfigV2ConfigurationHarness.m,
//  except for the `initWithConfig:` wiring group at the bottom, which needs the
//  whole SDK object graph and therefore only runs under XCTest.
//

#import <XCTest/XCTest.h>

#import "QNAPIConstants.h"
#import "QNProductCenterManager.h"
#import "QONConfiguration.h"
#import "QONRemoteConfigController+Protected.h"
#import "QONRemoteConfigManager.h"
#import "QONRemoteConfigV2Configuration.h"
#import "QONRemoteConfigV2Configuration+Protected.h"
#import "Qonversion.h"

/**
 The two private entry points the wiring group drives.

 Declared here rather than exported, because the surface under test is precisely
 that `initWithConfig:` reaches the controller — not that anything else may.
 */
@interface Qonversion (QONRemoteConfigV2ConfigurationTests)
- (instancetype)initWithCustomUserDefaults:(NSUserDefaults *)userDefaults;
- (void)configureExperimentalRemoteConfigWithConfiguration:(QONRemoteConfigV2Configuration *)configuration
                                                projectKey:(NSString *)projectKey
                                                sdkVersion:(NSString *)sdkVersion;
/** The v1 surface, so a dormancy test can prove it was left alone. */
@property (nonatomic, strong, readonly) QONRemoteConfigManager *remoteConfigManager;
@property (nonatomic, strong, readonly) QNProductCenterManager *productCenterManager;
@end

/** A gateway nothing can reach, so no test can leave the machine. */
static NSString *const kUnreachableGateway = @"https://gateway.invalid/";

@interface QONRemoteConfigV2ConfigurationTests : XCTestCase
@end

@implementation QONRemoteConfigV2ConfigurationTests

#pragma mark - Helpers

/** A string of `count` code points, each one outside the BMP. */
- (NSString *)astralStringOfCodePoints:(NSUInteger)count {
  NSMutableString *value = [NSMutableString new];
  for (NSUInteger index = 0; index < count; index++) {
    [value appendString:@"😀"];
  }
  return value;
}

#pragma mark - Addressing

- (void)testTheProductionInitializerAddressesTheProductionGateway {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];

  XCTAssertEqualObjects(configuration.baseURL, kRemoteConfigV2APIBase);
  XCTAssertEqualObjects(configuration.baseURL, @"https://api2.qonversion.io/");
  XCTAssertEqualObjects(configuration.environmentUid, @"env-uid");
  XCTAssertEqual(configuration.minimumFetchIntervalMilliseconds, 0);
}

- (void)testAnExplicitGatewayIsKeptVerbatim {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithBaseURL:@"http://localhost:8080/gateway"
                                               environmentUid:@"env-uid"];

  // No trailing slash is added and no path is dropped: the transport composes
  // the route on top of whatever prefix the caller stated.
  XCTAssertEqualObjects(configuration.baseURL, @"http://localhost:8080/gateway");
}

#pragma mark - Base URL validation

- (void)testEveryAbsoluteHTTPURLIsAccepted {
  NSArray<NSString *> *accepted = @[
    @"https://gateway.example.com/",
    @"https://gateway.example.com",
    @"http://gateway.example.com/",
    @"https://gateway.example.com:8443/prefix/",
    @"https://user:pass@gateway.example.com/",
  ];

  for (NSString *baseURL in accepted) {
    XCTAssertNoThrow([[QONRemoteConfigV2Configuration alloc] initWithBaseURL:baseURL
                                                             environmentUid:@"env-uid"],
                     @"%@ must be accepted", baseURL);
  }
}

- (void)testEveryMalformedBaseURLIsRefused {
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
    XCTAssertThrowsSpecificNamed([[QONRemoteConfigV2Configuration alloc] initWithBaseURL:baseURL
                                                                         environmentUid:@"env-uid"],
                                 NSException, NSInvalidArgumentException,
                                 @"%@ must be refused", baseURL);
  }
}

- (void)testANilBaseURLIsRefused {
  XCTAssertThrowsSpecificNamed([[QONRemoteConfigV2Configuration alloc] initWithBaseURL:(NSString *_Nonnull)nil
                                                                       environmentUid:@"env-uid"],
                               NSException, NSInvalidArgumentException);
}

#pragma mark - Environment uid validation

- (void)testTheEnvironmentUidLengthEdgesAreCountedInCodePoints {
  XCTAssertNoThrow([[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"e"]);
  XCTAssertNoThrow([[QONRemoteConfigV2Configuration alloc]
      initWithEnvironmentUid:[@"" stringByPaddingToLength:36 withString:@"e" startingAtIndex:0]]);
  XCTAssertThrowsSpecificNamed(
      [[QONRemoteConfigV2Configuration alloc]
          initWithEnvironmentUid:[@"" stringByPaddingToLength:37 withString:@"e" startingAtIndex:0]],
      NSException, NSInvalidArgumentException);
}

- (void)testAMultiByteEnvironmentUidIsMeasuredInCodePointsNotUnits {
  // 36 astral code points are 72 UTF-16 units and 144 UTF-8 bytes. Counting
  // either of those would refuse a uid the gateway accepts.
  NSString *thirtySix = [self astralStringOfCodePoints:36];
  XCTAssertEqual(thirtySix.length, 72u);
  XCTAssertNoThrow([[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:thirtySix]);

  XCTAssertThrowsSpecificNamed(
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:[self astralStringOfCodePoints:37]],
      NSException, NSInvalidArgumentException);
}

- (void)testAnEmptyOrNilEnvironmentUidIsRefused {
  XCTAssertThrowsSpecificNamed([[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@""],
                               NSException, NSInvalidArgumentException);
  XCTAssertThrowsSpecificNamed(
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:(NSString *_Nonnull)nil],
      NSException, NSInvalidArgumentException);
}

#pragma mark - Minimum fetch interval

- (void)testTheMinimumFetchIntervalDefaultsToAutomaticAndRefusesNegatives {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];

  XCTAssertEqual(configuration.minimumFetchIntervalMilliseconds, 0);

  [configuration setMinimumFetchIntervalMilliseconds:5000];
  XCTAssertEqual(configuration.minimumFetchIntervalMilliseconds, 5000);

  XCTAssertThrowsSpecificNamed([configuration setMinimumFetchIntervalMilliseconds:-1],
                               NSException, NSInvalidArgumentException);
  XCTAssertEqual(configuration.minimumFetchIntervalMilliseconds, 5000);
}

- (void)testAnAutomaticIntervalMeansNoThrottleInDebugAndTheBuiltInOneInRelease {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];

  XCTAssertEqualObjects([configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                            QONRemoteConfigV2ReadGuardBuildModeDebug],
                        @0);
  XCTAssertNil([configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                   QONRemoteConfigV2ReadGuardBuildModeRelease]);
}

- (void)testAStatedIntervalWinsInEveryBuildMode {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithEnvironmentUid:@"env-uid"];
  [configuration setMinimumFetchIntervalMilliseconds:1234];

  XCTAssertEqualObjects([configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                            QONRemoteConfigV2ReadGuardBuildModeDebug],
                        @1234);
  XCTAssertEqualObjects([configuration effectiveMinimumFetchIntervalMillisecondsForBuildMode:
                            QONRemoteConfigV2ReadGuardBuildModeRelease],
                        @1234);
}

#pragma mark - Copying

- (void)testACopyCarriesEveryField {
  QONRemoteConfigV2Configuration *configuration =
      [[QONRemoteConfigV2Configuration alloc] initWithBaseURL:@"https://gateway.example.com/"
                                               environmentUid:@"env-uid"];
  [configuration setMinimumFetchIntervalMilliseconds:7000];

  QONRemoteConfigV2Configuration *copy = [configuration copy];

  XCTAssertNotIdentical(copy, configuration);
  XCTAssertEqualObjects(copy.baseURL, @"https://gateway.example.com/");
  XCTAssertEqualObjects(copy.environmentUid, @"env-uid");
  XCTAssertEqual(copy.minimumFetchIntervalMilliseconds, 7000);

  // The copy is its own object: changing it must not reach the original.
  [copy setMinimumFetchIntervalMilliseconds:1];
  XCTAssertEqual(configuration.minimumFetchIntervalMilliseconds, 7000);
}

#pragma mark - QONConfiguration carry

- (void)testTheSDKConfigurationLeavesTheSurfaceOffByDefault {
  QONConfiguration *configuration =
      [[QONConfiguration alloc] initWithProjectKey:@"project-key"
                                        launchMode:QONLaunchModeSubscriptionManagement];

  QONConfiguration *copy = [configuration copy];

  XCTAssertNil(configuration.remoteConfigV2Configuration);
  XCTAssertNil(copy.remoteConfigV2Configuration);
}

- (void)testTheSDKConfigurationCopiesTheRemoteConfigConfigurationAndCarriesItThroughACopy {
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
  XCTAssertEqual(configuration.remoteConfigV2Configuration.minimumFetchIntervalMilliseconds, 9000);

  QONConfiguration *copy = [configuration copy];
  XCTAssertEqualObjects(copy.remoteConfigV2Configuration.baseURL, @"https://gateway.example.com/");
  XCTAssertEqualObjects(copy.remoteConfigV2Configuration.environmentUid, @"env-uid");
  XCTAssertEqual(copy.remoteConfigV2Configuration.minimumFetchIntervalMilliseconds, 9000);

  [configuration setRemoteConfigV2Configuration:nil];
  XCTAssertNil(configuration.remoteConfigV2Configuration);
}

- (void)testTheGetterHandsOutACopySoNobodyCanReconfigureTheSDKThroughIt {
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

  XCTAssertEqual(configuration.remoteConfigV2Configuration.minimumFetchIntervalMilliseconds, 9000);
  XCTAssertNotIdentical(configuration.remoteConfigV2Configuration,
                        configuration.remoteConfigV2Configuration);
}

#pragma mark - initWithConfig: wiring

- (void)testTheSurfaceStaysDormantWithoutARemoteConfigConfiguration {
  NSString *suiteName = [NSString stringWithFormat:@"io.qonversion.tests.%@",
                                                   NSUUID.UUID.UUIDString];
  NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
  Qonversion *instance = [[Qonversion alloc] initWithCustomUserDefaults:suite];

  [instance configureExperimentalRemoteConfigWithConfiguration:nil
                                                    projectKey:@"project-key"
                                                    sdkVersion:@"9.9.9"];

  XCTAssertNotNil(instance.experimentalRemoteConfig);
  XCTAssertFalse(instance.experimentalRemoteConfig.isConfigured);
  XCTAssertEqual(instance.experimentalRemoteConfig.installedMinimumFetchIntervalMilliseconds, -1);

  // The v1 surface is a separate object with its own lifetime, and leaving v2
  // dormant must not have disturbed it or its wiring.
  XCTAssertNotNil(instance.remoteConfigManager);
  XCTAssertIdentical(instance.productCenterManager.remoteConfigManager,
                     instance.remoteConfigManager);

  // Nothing of the v2 engine reached storage, because none of it was built.
  for (NSString *key in [suite dictionaryRepresentation].allKeys) {
    XCTAssertFalse([key containsString:@"remote-config-v2"], @"unexpected v2 key %@", key);
  }

  [suite removePersistentDomainForName:suiteName];
}

- (void)testARemoteConfigConfigurationBringsTheSurfaceOnline {
  Qonversion *instance = [[Qonversion alloc] initWithCustomUserDefaults:[NSUserDefaults standardUserDefaults]];
  QONRemoteConfigV2Configuration *remoteConfigConfiguration =
      [[QONRemoteConfigV2Configuration alloc] initWithBaseURL:kUnreachableGateway
                                               environmentUid:@"env-uid"];
  [remoteConfigConfiguration setMinimumFetchIntervalMilliseconds:4242];

  [instance configureExperimentalRemoteConfigWithConfiguration:remoteConfigConfiguration
                                                    projectKey:@"project-key"
                                                    sdkVersion:@"9.9.9"];

  XCTAssertTrue(instance.experimentalRemoteConfig.isConfigured);
  // The stated interval reached the fetch policy rather than being dropped on
  // the way through the assembly.
  XCTAssertEqual(instance.experimentalRemoteConfig.installedMinimumFetchIntervalMilliseconds, 4242);
}

@end
