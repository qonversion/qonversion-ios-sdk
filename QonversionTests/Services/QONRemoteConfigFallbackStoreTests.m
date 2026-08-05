//
//  QONRemoteConfigFallbackStoreTests.m
//  QonversionTests
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

#import "QONRemoteConfigFallbackStore.h"
#import "QONRemoteConfigV2Models.h"
#import "Qonversion.h"

static NSString *const kRemoteConfigDefaultsFileName = @"qonversion_remote_config_defaults";
static NSString *const kRemoteConfigDefaultsFileExtension = @"json";
static NSString *const kEscapedSurrogateManifestHash =
    @"e2d2e6cd92b6aca3bae40d4196bcedb6beade7b3dbf672bc13193b3dd9e7ad02";

static NSData *QONTestASCIIData(NSString *value) {
  return [value dataUsingEncoding:NSASCIIStringEncoding];
}

static void QONTestAppendDigestPart(CC_SHA256_CTX *context, NSData *part) {
  uint64_t length = CFSwapInt64HostToBig((uint64_t)part.length);
  CC_SHA256_Update(context, &length, (CC_LONG)sizeof(length));
  CC_SHA256_Update(context, part.bytes, (CC_LONG)part.length);
}

static NSString *QONTestSingleDefaultDigest(int64_t projectID,
                                             int64_t releaseNumber,
                                             NSData *rawValue) {
  CC_SHA256_CTX context;
  CC_SHA256_Init(&context);
  NSArray<NSData *> *parts = @[
    QONTestASCIIData(@"qonversion.remote-config-fallback-defaults.v1"),
    QONTestASCIIData(@"1"),
    QONTestASCIIData([NSString stringWithFormat:@"%lld", (long long)projectID]),
    [@"env-production" dataUsingEncoding:NSUTF8StringEncoding],
    [@"release-escaped-surrogate" dataUsingEncoding:NSUTF8StringEncoding],
    QONTestASCIIData([NSString stringWithFormat:@"%lld", (long long)releaseNumber]),
    QONTestASCIIData(kEscapedSurrogateManifestHash),
    QONTestASCIIData(@"1"),
    [@"escaped_pair" dataUsingEncoding:NSUTF8StringEncoding],
    [@"variation-escaped-pair" dataUsingEncoding:NSUTF8StringEncoding],
    rawValue,
  ];
  for (NSData *part in parts) {
    QONTestAppendDigestPart(&context, part);
  }
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(digest, &context);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return hex;
}

static NSData *QONTestSingleDefaultArtifact(int64_t projectID,
                                             int64_t releaseNumber,
                                             NSString *rawJSON) {
  NSData *rawValue = [rawJSON dataUsingEncoding:NSUTF8StringEncoding];
  NSString *encoded = [rawValue base64EncodedStringWithOptions:0];
  NSString *digest = QONTestSingleDefaultDigest(projectID, releaseNumber, rawValue);
  NSString *artifact = [NSString stringWithFormat:
      @"{\"schemaVersion\":1,\"projectId\":%lld,\"environmentUid\":\"env-production\","
       @"\"releaseUid\":\"release-escaped-surrogate\",\"releaseNumber\":%lld,"
       @"\"manifestContentHash\":\"%@\",\"defaultsDigest\":\"%@\","
       @"\"defaults\":[{\"key\":\"escaped_pair\",\"variationUid\":\"variation-escaped-pair\","
       @"\"valueBase64\":\"%@\"}]}",
      (long long)projectID, (long long)releaseNumber,
      kEscapedSurrogateManifestHash, digest, encoded];
  return [artifact dataUsingEncoding:NSUTF8StringEncoding];
}

@interface QONRemoteConfigFallbackStoreTests : XCTestCase
@end

@implementation QONRemoteConfigFallbackStoreTests

- (NSDictionary *)goldenManifest {
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSURL *url = [bundle URLForResource:kRemoteConfigDefaultsFileName
                        withExtension:kRemoteConfigDefaultsFileExtension];
  XCTAssertNotNil(url);

  NSData *data = [NSData dataWithContentsOfURL:url];
  XCTAssertNotNil(data);

  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([object isKindOfClass:NSDictionary.class]);
  return object;
}

- (NSDictionary *)allTypesManifest {
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSURL *url = [bundle URLForResource:@"qonversion_remote_config_defaults_all_types"
                        withExtension:kRemoteConfigDefaultsFileExtension];
  XCTAssertNotNil(url);
  NSData *data = [NSData dataWithContentsOfURL:url];
  XCTAssertNotNil(data);
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  XCTAssertTrue([object isKindOfClass:NSDictionary.class]);
  return object;
}

- (QONRemoteConfigFallbackStore *)storeWithFixtureNamed:(NSString *)name {
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSURL *url = [bundle URLForResource:name withExtension:kRemoteConfigDefaultsFileExtension];
  XCTAssertNotNil(url);
  NSData *data = [NSData dataWithContentsOfURL:url];
  XCTAssertNotNil(data);
  return [[QONRemoteConfigFallbackStore alloc]
      initWithBundle:[self bundleWithFileName:@"qonversion_remote_config_defaults.json" data:data]];
}

- (NSData *)fixtureDataNamed:(NSString *)name {
  NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:name
                                                   withExtension:kRemoteConfigDefaultsFileExtension];
  XCTAssertNotNil(url);
  NSData *data = [NSData dataWithContentsOfURL:url];
  XCTAssertNotNil(data);
  return data;
}

- (QONRemoteConfigFallbackStore *)storeWithEncodedArtifact:(NSData *)data {
  return [[QONRemoteConfigFallbackStore alloc]
      initWithBundle:[self bundleWithFileName:@"qonversion_remote_config_defaults.json" data:data]];
}

- (NSBundle *)bundleWithFileName:(NSString *)fileName data:(NSData *)data {
  NSString *bundlePath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bundle", NSUUID.UUID.UUIDString]];
  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:bundlePath
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error]);
  XCTAssertNil(error);

  NSDictionary *info = @{
    @"CFBundleIdentifier": [NSString stringWithFormat:@"io.qonversion.tests.%@", NSUUID.UUID.UUIDString],
    @"CFBundleName": @"RemoteConfigFallbackFixture",
    @"CFBundlePackageType": @"BNDL",
  };
  XCTAssertTrue([info writeToFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);

  if (data) {
    XCTAssertTrue([data writeToFile:[bundlePath stringByAppendingPathComponent:fileName]
                           options:NSDataWritingAtomic
                             error:&error]);
    XCTAssertNil(error);
  }

  NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
  XCTAssertNotNil(bundle);
  return bundle;
}

- (NSBundle *)bundleWithManifest:(NSDictionary *)manifest {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(data);
  return [self bundleWithFileName:@"qonversion_remote_config_defaults.json" data:data];
}

- (QONRemoteConfigFallbackStore *)storeWithManifest:(NSDictionary *)manifest {
  return [[QONRemoteConfigFallbackStore alloc] initWithBundle:[self bundleWithManifest:manifest]];
}

- (NSMutableDictionary *)mutableGoldenManifest {
  NSMutableDictionary *manifest = [[self goldenManifest] mutableCopy];
  NSMutableArray *defaults = [NSMutableArray new];
  for (NSDictionary *entry in manifest[@"defaults"]) {
    [defaults addObject:[entry mutableCopy]];
  }
  manifest[@"defaults"] = defaults;
  return manifest;
}

- (NSMutableDictionary *)mutableAllTypesManifest {
  NSMutableDictionary *manifest = [[self allTypesManifest] mutableCopy];
  NSMutableArray *defaults = [NSMutableArray new];
  for (NSDictionary *entry in manifest[@"defaults"]) {
    [defaults addObject:[entry mutableCopy]];
  }
  manifest[@"defaults"] = defaults;
  return manifest;
}

- (void)testReadsServerGoldenArtifactByteForByteContract {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:kRemoteConfigDefaultsFileName];
  XCTAssertEqualObjects([store valueForContextKey:@"alpha"], (@{@"message": @"Привет 👋"}));
  XCTAssertEqualObjects([store valueForContextKey:@"beta"], NSNull.null);
}

- (void)testReadsEverySupportedJSONValueFromGoldenManifest {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:@"qonversion_remote_config_defaults_all_types"];

  XCTAssertEqualObjects([store valueForContextKey:@"array"], (@[@1, @"two", @NO]));
  XCTAssertEqualObjects([store valueForContextKey:@"bool"], @YES);
  XCTAssertEqualObjects([store valueForContextKey:@"null"], NSNull.null);
  XCTAssertEqualObjects([store valueForContextKey:@"number"], @42.5);
  XCTAssertEqualObjects([store valueForContextKey:@"object"], (@{@"enabled": @YES, @"nested": @"value"}));
  XCTAssertEqualObjects([store valueForContextKey:@"string"], @"hello");
  XCTAssertEqualObjects([store valueForContextKey:@"unicode"], @"Привет 👋");
}

- (void)testExposesExactRawDefaultsAsOneValidatedFallbackRelease {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:@"qonversion_remote_config_defaults_all_types"];
  QONRemoteConfigV2Release *release = [store remoteConfigV2FallbackRelease];

  XCTAssertNotNil(release);
  XCTAssertEqual(store.projectID, 42);
  XCTAssertEqualObjects(store.environmentUID, @"env-production");
  XCTAssertEqualObjects(release.releaseUID, @"release-all-json-types");
  XCTAssertEqualObjects([store rawValueForContextKey:@"string"],
                        [@"\"hello\"" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(release.entries[@"string"].rawData,
                        [@"\"hello\"" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqual(release.entries[@"string"].applyPolicy,
                 QONRemoteConfigApplyPolicyOnNextActivate);
}

- (void)testAcceptsPortableJSONNumberBoundariesFromProducerGolden {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:@"qonversion_remote_config_defaults_number_boundaries"];
  XCTAssertEqualWithAccuracy([[store valueForContextKey:@"float_max"] doubleValue], 1e308, 0.0);
  XCTAssertEqualObjects([store valueForContextKey:@"int_max"], @9007199254740991LL);
  XCTAssertEqualObjects([store valueForContextKey:@"int_min"], @(-9007199254740991LL));
}

- (void)testReturnsNilForMissingContextKey {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:@"qonversion_remote_config_defaults_all_types"];
  XCTAssertNil([store valueForContextKey:@"missing"]);
  XCTAssertNil([store valueForContextKey:nil]);
}

- (void)testReturnedContainersCannotMutateCachedValues {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:@"qonversion_remote_config_defaults_all_types"];

  NSDictionary *first = [store valueForContextKey:@"object"];
  XCTAssertFalse([first isKindOfClass:NSMutableDictionary.class]);
  NSMutableDictionary *callerCopy = [first mutableCopy];
  callerCopy[@"nested"] = @"changed";

  XCTAssertEqualObjects([store valueForContextKey:@"object"], (@{@"enabled": @YES, @"nested": @"value"}));
}

- (void)testValidatesExactRawJSONBytesThroughGoldenDigest {
  NSMutableDictionary *manifest = [self mutableAllTypesManifest];
  NSMutableDictionary *unicode = manifest[@"defaults"][6];
  NSData *escapedJSON = [@"\"\\u041f\\u0440\\u0438\\u0432\\u0435\\u0442 \\ud83d\\udc4b\""
      dataUsingEncoding:NSUTF8StringEncoding];
  unicode[@"valueBase64"] = [escapedJSON base64EncodedStringWithOptions:0];

  // The decoded value is semantically identical, but the producer digest is
  // over the exact raw JSON bytes and therefore must reject this artifact.
  QONRemoteConfigFallbackStore *store = [self storeWithManifest:manifest];
  XCTAssertNil([store valueForContextKey:@"unicode"]);
}

- (void)testRejectsDigestMismatch {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  manifest[@"defaultsDigest"] = @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsUnknownSchema {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  manifest[@"schemaVersion"] = @2;
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsMissingRequiredHeader {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  [manifest removeObjectForKey:@"releaseUid"];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsNonPositiveOrNonIntegralScopeNumbers {
  NSMutableDictionary *zeroProject = [self mutableGoldenManifest];
  zeroProject[@"projectId"] = @0;
  XCTAssertNil([[self storeWithManifest:zeroProject] valueForContextKey:@"alpha"]);

  NSMutableDictionary *negativeRelease = [self mutableGoldenManifest];
  negativeRelease[@"releaseNumber"] = @(-1);
  XCTAssertNil([[self storeWithManifest:negativeRelease] valueForContextKey:@"alpha"]);

  NSString *golden = [[NSString alloc] initWithData:[self fixtureDataNamed:kRemoteConfigDefaultsFileName]
                                           encoding:NSUTF8StringEncoding];
  NSString *floatingProject = [golden stringByReplacingOccurrencesOfString:@"\"projectId\":42"
                                                                withString:@"\"projectId\":42.0"];
  XCTAssertNil([[self storeWithEncodedArtifact:[floatingProject dataUsingEncoding:NSUTF8StringEncoding]]
      valueForContextKey:@"alpha"]);
}

- (void)testRejectsUppercaseOrMalformedHex {
  NSMutableDictionary *uppercaseHash = [self mutableGoldenManifest];
  uppercaseHash[@"manifestContentHash"] = [uppercaseHash[@"manifestContentHash"] uppercaseString];
  XCTAssertNil([[self storeWithManifest:uppercaseHash] valueForContextKey:@"bool"]);

  NSMutableDictionary *shortDigest = [self mutableGoldenManifest];
  shortDigest[@"defaultsDigest"] = @"00";
  XCTAssertNil([[self storeWithManifest:shortDigest] valueForContextKey:@"bool"]);
}

- (void)testRejectsNonCanonicalBase64 {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][1];
  entry[@"valueBase64"] = @"dHJ1ZQ"; // canonical form is dHJ1ZQ==
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsInvalidRawJSON {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][1];
  entry[@"valueBase64"] = [[@"not-json" dataUsingEncoding:NSUTF8StringEncoding]
      base64EncodedStringWithOptions:0];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsDuplicateMembersInsideRawJSONValue {
  NSMutableDictionary *manifest = [self mutableAllTypesManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][4];
  entry[@"valueBase64"] = [[@"{\"duplicate\":1,\"duplicate\":2}"
      dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"object"]);
}

- (void)testRejectsRawJSONDeeperThanSixtyFourContainers {
  NSMutableString *nested = [NSMutableString new];
  for (NSUInteger index = 0; index < 65; index++) [nested appendString:@"["];
  [nested appendString:@"null"];
  for (NSUInteger index = 0; index < 65; index++) [nested appendString:@"]"];

  NSMutableDictionary *manifest = [self mutableAllTypesManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][0];
  entry[@"valueBase64"] = [[nested dataUsingEncoding:NSUTF8StringEncoding]
      base64EncodedStringWithOptions:0];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"array"]);
}

- (void)testRejectsInvalidUTF8RawJSON {
  const uint8_t bytes[] = {0x22, 0xff, 0x22};
  NSMutableDictionary *manifest = [self mutableAllTypesManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][5];
  entry[@"valueBase64"] = [[NSData dataWithBytes:bytes length:sizeof(bytes)]
      base64EncodedStringWithOptions:0];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"string"]);
}

- (void)testRejectsNonFiniteBinary64JSONNumber {
  NSMutableDictionary *manifest = [self mutableAllTypesManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][3];
  entry[@"valueBase64"] = [[@"1e309" dataUsingEncoding:NSUTF8StringEncoding]
      base64EncodedStringWithOptions:0];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"number"]);
}

- (void)testEscapedSurrogatePairsMatchPortableProducerProfile {
  QONRemoteConfigFallbackStore *valid = [self storeWithEncodedArtifact:
      QONTestSingleDefaultArtifact(42, 10, @"\"\\ud83d\\udc4b\"")];
  XCTAssertEqualObjects([valid valueForContextKey:@"escaped_pair"], @"👋");

  for (NSString *raw in @[@"\"\\ud83d\"", @"\"\\ud83d\\u0041\"", @"\"\\udc4b\""]) {
    QONRemoteConfigFallbackStore *invalid = [self storeWithEncodedArtifact:
        QONTestSingleDefaultArtifact(42, 10, raw)];
    XCTAssertNil([invalid valueForContextKey:@"escaped_pair"], @"%@", raw);
  }
}

- (void)testHeaderIntegersMustRemainExactlyPortableAcrossSDKs {
  XCTAssertNil([[self storeWithEncodedArtifact:
      QONTestSingleDefaultArtifact(9007199254740992LL, 10, @"true")]
      valueForContextKey:@"escaped_pair"]);
  XCTAssertNil([[self storeWithEncodedArtifact:
      QONTestSingleDefaultArtifact(42, 9007199254740992LL, @"true")]
      valueForContextKey:@"escaped_pair"]);
}

- (void)testRejectsPlainIntegersOutsidePortableExactRange {
  for (NSString *raw in @[@"9007199254740992", @"-9007199254740992"]) {
    NSMutableDictionary *manifest = [self mutableAllTypesManifest];
    NSMutableDictionary *entry = manifest[@"defaults"][3];
    entry[@"valueBase64"] = [[raw dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    QONRemoteConfigFallbackStore *store = [self storeWithManifest:manifest];
    XCTAssertNil([store valueForContextKey:@"number"]);
    XCTAssertNil([store valueForContextKey:@"bool"]);
  }
}

- (void)testOneCorruptDefaultPreventsEveryArtifactValueFromBeingExposed {
  NSMutableDictionary *manifest = [self mutableAllTypesManifest];
  NSArray *defaults = manifest[@"defaults"];
  NSMutableDictionary *lastEntry = defaults.lastObject;
  lastEntry[@"valueBase64"] = [[@"not-json" dataUsingEncoding:NSUTF8StringEncoding]
      base64EncodedStringWithOptions:0];

  QONRemoteConfigFallbackStore *store = [self storeWithManifest:manifest];
  XCTAssertNil([store valueForContextKey:@"array"]);
  XCTAssertNil([store valueForContextKey:@"bool"]);
}

- (void)testRejectsUnsortedKeys {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  NSMutableArray *defaults = manifest[@"defaults"];
  [defaults exchangeObjectAtIndex:0 withObjectAtIndex:1];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsDuplicateKeys {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  NSMutableArray *defaults = manifest[@"defaults"];
  [defaults insertObject:[defaults.firstObject mutableCopy] atIndex:1];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"array"]);
}

- (void)testRejectsEmptyOrOversizedKeyAndUIDs {
  NSMutableDictionary *emptyKey = [self mutableAllTypesManifest];
  emptyKey[@"defaults"][0][@"key"] = @"";
  XCTAssertNil([[self storeWithManifest:emptyKey] valueForContextKey:@""]);

  NSMutableDictionary *oversizedKey = [self mutableAllTypesManifest];
  oversizedKey[@"defaults"][0][@"key"] = [@"é" stringByPaddingToLength:258
                                                                withString:@"é"
                                                           startingAtIndex:0];
  XCTAssertNil([[self storeWithManifest:oversizedKey] valueForContextKey:@"array"]);

  NSMutableDictionary *oversizedUID = [self mutableAllTypesManifest];
  oversizedUID[@"defaults"][0][@"variationUid"] = [@"x" stringByPaddingToLength:37
                                                                           withString:@"x"
                                                                      startingAtIndex:0];
  XCTAssertNil([[self storeWithManifest:oversizedUID] valueForContextKey:@"array"]);

  NSMutableDictionary *oversizedEnvironment = [self mutableAllTypesManifest];
  oversizedEnvironment[@"environmentUid"] = [@"👋" stringByPaddingToLength:74
                                                                     withString:@"👋"
                                                                startingAtIndex:0];
  XCTAssertNil([[self storeWithManifest:oversizedEnvironment] valueForContextKey:@"array"]);
}

- (void)testRejectsMoreThanOneThousandDefaults {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  NSMutableArray *defaults = [NSMutableArray new];
  for (NSUInteger index = 0; index < 1001; index++) {
    [defaults addObject:@{
      @"key": [NSString stringWithFormat:@"key-%04lu", (unsigned long)index],
      @"variationUid": @"variation",
      @"valueBase64": @"bnVsbA==",
    }];
  }
  manifest[@"defaults"] = defaults;
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"key-0000"]);
}

- (void)testRejectsDecodedValueLargerThanSixtyFourKiB {
  NSMutableDictionary *manifest = [self mutableGoldenManifest];
  NSMutableDictionary *entry = manifest[@"defaults"][1];
  NSMutableData *oversizedJSON = [NSMutableData dataWithLength:64 * 1024 + 1];
  memset(oversizedJSON.mutableBytes, ' ', oversizedJSON.length);
  ((uint8_t *)oversizedJSON.mutableBytes)[0] = '0';
  entry[@"valueBase64"] = [oversizedJSON base64EncodedStringWithOptions:0];
  XCTAssertNil([[self storeWithManifest:manifest] valueForContextKey:@"bool"]);
}

- (void)testRejectsFileLargerThanEightMiBBeforeParsing {
  NSMutableData *data = [NSMutableData dataWithLength:8 * 1024 * 1024 + 1];
  memset(data.mutableBytes, ' ', data.length);
  QONRemoteConfigFallbackStore *store = [[QONRemoteConfigFallbackStore alloc]
      initWithBundle:[self bundleWithFileName:@"qonversion_remote_config_defaults.json" data:data]];
  XCTAssertNil([store valueForContextKey:@"bool"]);
}

- (void)testRejectsNonCanonicalWhitespaceUnknownAndDuplicateRootFields {
  NSData *goldenData = [self fixtureDataNamed:kRemoteConfigDefaultsFileName];

  NSMutableData *withNewline = [goldenData mutableCopy];
  const uint8_t newline = '\n';
  [withNewline appendBytes:&newline length:1];
  XCTAssertNil([[self storeWithEncodedArtifact:withNewline] valueForContextKey:@"alpha"]);

  NSString *golden = [[NSString alloc] initWithData:goldenData encoding:NSUTF8StringEncoding];
  NSString *withUnknown = [golden stringByReplacingOccurrencesOfString:@",\"defaults\":["
                                                              withString:@",\"unknown\":true,\"defaults\":["];
  XCTAssertNil([[self storeWithEncodedArtifact:[withUnknown dataUsingEncoding:NSUTF8StringEncoding]]
      valueForContextKey:@"alpha"]);

  NSString *withDuplicate = [golden stringByReplacingOccurrencesOfString:@"{\"schemaVersion\":1,"
                                                                withString:@"{\"schemaVersion\":1,\"schemaVersion\":1,"];
  XCTAssertNil([[self storeWithEncodedArtifact:[withDuplicate dataUsingEncoding:NSUTF8StringEncoding]]
      valueForContextKey:@"alpha"]);

  NSString *withUnknownDefaultField = [golden
      stringByReplacingOccurrencesOfString:@"{\"key\":\"alpha\""
                                 withString:@"{\"unknown\":true,\"key\":\"alpha\""];
  XCTAssertNil([[self storeWithEncodedArtifact:[withUnknownDefaultField dataUsingEncoding:NSUTF8StringEncoding]]
      valueForContextKey:@"alpha"]);
}

- (void)testDoesNotAcceptLegacyFallbackFile {
  NSError *error = nil;
  NSData *legacyData = [NSJSONSerialization dataWithJSONObject:@{
    @"remote_config_list": @[@{
      @"payload": @{@"bool": @YES},
      @"source": @{@"context_key": @"bool"},
    }],
  } options:0 error:&error];
  XCTAssertNil(error);

  QONRemoteConfigFallbackStore *store = [[QONRemoteConfigFallbackStore alloc]
      initWithBundle:[self bundleWithFileName:@"qonversion_ios_fallbacks.json" data:legacyData]];
  XCTAssertNil([store valueForContextKey:@"bool"]);
}

- (void)testCachesTheValidatedImmutableArtifactForTheLifetimeOfTheStore {
  NSData *goldenData = [self fixtureDataNamed:kRemoteConfigDefaultsFileName];
  NSBundle *bundle = [self bundleWithFileName:@"qonversion_remote_config_defaults.json" data:goldenData];
  QONRemoteConfigFallbackStore *store = [[QONRemoteConfigFallbackStore alloc] initWithBundle:bundle];
  XCTAssertEqualObjects([store valueForContextKey:@"alpha"], (@{@"message": @"Привет 👋"}));

  NSURL *artifact = [bundle.bundleURL URLByAppendingPathComponent:@"qonversion_remote_config_defaults.json"];
  XCTAssertTrue([[@"{}" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:artifact atomically:YES]);
  XCTAssertEqualObjects([store valueForContextKey:@"alpha"], (@{@"message": @"Привет 👋"}));

  QONRemoteConfigFallbackStore *freshStore = [[QONRemoteConfigFallbackStore alloc]
      initWithBundle:[NSBundle bundleWithPath:bundle.bundlePath]];
  XCTAssertNil([freshStore valueForContextKey:@"alpha"]);
}

- (void)testConcurrentReadsShareAValidatedImmutableCache {
  QONRemoteConfigFallbackStore *store = [self storeWithFixtureNamed:@"qonversion_remote_config_defaults_all_types"];
  dispatch_group_t group = dispatch_group_create();
  dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  NSObject *failuresLock = [NSObject new];
  __block NSUInteger failures = 0;

  for (NSUInteger index = 0; index < 500; index++) {
    dispatch_group_async(group, queue, ^{
      id value = [store valueForContextKey:@"unicode"];
      if (![value isEqual:@"Привет 👋"]) {
        @synchronized (failuresLock) {
          failures += 1;
        }
      }
    });
  }

  XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);
  XCTAssertEqual(failures, 0);
}

- (void)testPublicClassGetterReadsTheHostBundleWithoutSDKInitialization {
  // The class entry point is intentionally usable before initWithConfig:. The
  // Sample test host embeds the golden artifact as a main-bundle resource.
  XCTAssertEqualObjects([Qonversion fallbackRemoteConfigValueForContextKey:@"alpha"],
                        (@{@"message": @"Привет 👋"}));
}

- (void)testInstanceForwarderMatchesThePreInitClassGetterWithoutUsingInstanceState {
  Qonversion *uninitializedInstance = class_createInstance(Qonversion.class, 0);
  XCTAssertEqualObjects([uninitializedInstance fallbackRemoteConfigValueForContextKey:@"alpha"],
                        [Qonversion fallbackRemoteConfigValueForContextKey:@"alpha"]);
}

@end
