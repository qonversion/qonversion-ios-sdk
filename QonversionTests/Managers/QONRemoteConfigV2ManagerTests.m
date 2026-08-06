//
//  QONRemoteConfigV2ManagerTests.m
//  QonversionTests
//

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#import <xlocale.h>

#import "QNInMemoryStorage.h"
#import "QNLocalStorage.h"
#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigV2Manager.h"
#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigV2Store.h"

@interface QONRemoteConfigFailingStorage : NSObject <QNLocalStorage>
@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, assign) BOOL failWrites;
@property (nonatomic, assign) BOOL throwOnWrite;
@property (nonatomic, assign) NSUInteger readsToFail;
@property (nonatomic, copy, nullable) void (^writeObserver)(id object);
@end

@implementation QONRemoteConfigFailingStorage
- (instancetype)init { self = [super init]; if (self) _objects = [NSMutableDictionary new]; return self; }
- (void)storeObject:(id)object forKey:(NSString *)key {
  if (self.throwOnWrite) @throw [NSException exceptionWithName:@"WriteFailure" reason:nil userInfo:nil];
  if (!self.failWrites) {
    self.objects[key] = object;
    if (self.writeObserver) self.writeObserver(object);
  }
}
- (id)loadObjectForKey:(NSString *)key {
  if (self.readsToFail > 0) {
    self.readsToFail -= 1;
    @throw [NSException exceptionWithName:@"ReadFailure" reason:nil userInfo:nil];
  }
  return self.objects[key];
}
- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion([self loadObjectForKey:key]);
}
- (void)removeObjectForKey:(NSString *)key { [self.objects removeObjectForKey:key]; }
@end

@interface QONRemoteConfigBlockingEnvelopeDecoder : NSObject <QONRemoteConfigV2EnvelopeDecoding>
@property (nonatomic, strong) QONRemoteConfigV2EnvelopeParser *parser;
@property (nonatomic, strong) dispatch_semaphore_t started;
@property (nonatomic, strong) dispatch_semaphore_t resume;
@end

@implementation QONRemoteConfigBlockingEnvelopeDecoder
- (instancetype)init {
  self = [super init];
  if (self) {
    _parser = [QONRemoteConfigV2EnvelopeParser new];
    _started = dispatch_semaphore_create(0);
    _resume = dispatch_semaphore_create(0);
  }
  return self;
}
- (QONRemoteConfigV2Envelope *)parseBody:(NSData *)body
                              strongETag:(NSString *)strongETag
                             expectation:(QONRemoteConfigV2EnvelopeExpectation *)expectation {
  QONRemoteConfigV2Envelope *parsed = [self.parser parseBody:body
      strongETag:strongETag expectation:expectation];
  dispatch_semaphore_signal(self.started);
  dispatch_semaphore_wait(self.resume, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
  return parsed;
}
@end

@interface QONRemoteConfigV2ManagerTests : XCTestCase
@end

@implementation QONRemoteConfigV2ManagerTests

- (NSString *)strongETagForBody:(NSData *)body {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(body.bytes, (CC_LONG)body.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2 + 2];
  [hex appendString:@"\""];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  [hex appendString:@"\""];
  return hex;
}

- (NSString *)wireItemWithRaw:(NSString *)raw
                     metadata:(NSString *)metadata
                  variationUID:(NSString *)variationUID
                         policy:(NSString *)policy {
  return [NSString stringWithFormat:
      @"{\"raw\":%@,\"variation_uid\":\"%@\",\"apply_policy\":\"%@\",\"metadata\":%@}",
      raw, variationUID, policy, metadata];
}

- (NSString *)wireBodyWithValues:(NSString *)values {
  return [NSString stringWithFormat:
      @"{\"schema_version\":1,\"project_id\":42,\"environment_uid\":\"env-production\","
       "\"release_uid\":\"release\",\"release_number\":7,\"manifest_content_hash\":"
       "\"05b3abf2579a5eb66403cd78be557fd860633a1fe2103c7642030defe32c657f\","
       "\"complete_key_set\":true,\"context_fingerprint\":"
       "\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"values\":{%@}}",
      values];
}

- (QONRemoteConfigV2EnvelopeExpectation *)wireExpectation {
  return [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:42 environmentUID:@"env-production"
      contextFingerprint:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]];
}

- (QONRemoteConfigV2Scope *)wireScope:(NSString *)userID {
  return [[QONRemoteConfigV2Scope alloc] initWithProjectKey:@"project"
      environment:@"env-production" canonicalUserID:userID];
}

- (QONRemoteConfigV2Envelope *)parseWireBody:(NSString *)body {
  NSData *data = [self utf8Data:body];
  return [[QONRemoteConfigV2EnvelopeParser new] parseBody:data
      strongETag:[self strongETagForBody:data] expectation:[self wireExpectation]];
}

- (void)testCanonicalResolvedSnapshotWireBodyMatchesAndroidGoldenVectorExactly {
  NSString *bodyString = @"{\"schema_version\":1,\"project_id\":42,\"environment_uid\":\"env-production\",\"release_uid\":\"release-uid\",\"release_number\":7,\"manifest_content_hash\":\"05b3abf2579a5eb66403cd78be557fd860633a1fe2103c7642030defe32c657f\",\"complete_key_set\":true,\"context_fingerprint\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"values\":{\"alpha\":{\"raw\":\"value\",\"variation_uid\":\"variation-a\",\"apply_policy\":\"on_next_activate\",\"metadata\":null},\"zeta\":{\"raw\":{\"nested\":true},\"variation_uid\":\"variation-z\",\"apply_policy\":\"immediate\",\"metadata\":{\"resetNavigation\":true}}}}";
  NSData *body = [self utf8Data:bodyString];
  NSString *etag = @"\"d0c95fec2b0842242efdb0b8a034346538b7db97d6c5ff901501534ed940e3d3\"";

  QONRemoteConfigV2Envelope *envelope = [[QONRemoteConfigV2EnvelopeParser new]
      parseBody:body strongETag:etag expectation:[self wireExpectation]];

  XCTAssertNotNil(envelope);
  XCTAssertEqual(envelope.projectID, 42);
  XCTAssertEqualObjects(envelope.environmentUID, @"env-production");
  XCTAssertEqualObjects(envelope.eTag, etag);
  XCTAssertEqualObjects(envelope.bodyDigest,
                        @"d0c95fec2b0842242efdb0b8a034346538b7db97d6c5ff901501534ed940e3d3");
  XCTAssertEqualObjects(envelope.canonicalBody, body);
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"alpha"].rawData, [self utf8Data:@"\"value\""]);
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"alpha"].metadataData, [self utf8Data:@"null"]);
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"zeta"].rawData,
                        [self utf8Data:@"{\"nested\":true}"]);
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"zeta"].metadataData,
                        [self utf8Data:@"{\"resetNavigation\":true}"]);
  XCTAssertEqual(envelope.snapshotRelease.entries[@"zeta"].applyPolicy,
                 QONRemoteConfigApplyPolicyImmediate);
}

- (void)testWireParserRejectsETagScopeCompletenessAndMemberAmbiguity {
  NSString *item = [self wireItemWithRaw:@"true" metadata:@"null"
      variationUID:@"variation" policy:@"on_next_activate"];
  NSString *bodyString = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@", item]];
  NSData *body = [self utf8Data:bodyString];
  QONRemoteConfigV2EnvelopeParser *parser = [QONRemoteConfigV2EnvelopeParser new];
  NSString *validETag = [self strongETagForBody:body];

  XCTAssertNotNil([parser parseBody:body strongETag:validETag expectation:[self wireExpectation]]);
  XCTAssertNil([parser parseBody:body strongETag:[@"W/" stringByAppendingString:validETag]
      expectation:[self wireExpectation]]);
  XCTAssertNil([parser parseBody:body strongETag:validETag expectation:
      [[QONRemoteConfigV2EnvelopeExpectation alloc] initWithProjectID:43
          environmentUID:@"env-production"
          contextFingerprint:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]]]);
  XCTAssertNil([self parseWireBody:[bodyString stringByReplacingOccurrencesOfString:
      @"\"complete_key_set\":true" withString:@"\"complete_key_set\":false"]]);
  XCTAssertNil([self parseWireBody:[bodyString stringByReplacingOccurrencesOfString:
      @"\"schema_version\":1" withString:@"\"unknown\":0,\"schema_version\":1"]]);
  XCTAssertNil([self parseWireBody:[bodyString stringByReplacingOccurrencesOfString:
      @"\"schema_version\":1" withString:@"\"schema_version\":1,\"schema_\\u0076ersion\":1"]]);
}

- (void)testWireParserPreservesExactSpansAndRejectsNonPortableOrAmbiguousNestedJSON {
  NSString *raw = @" { \"a\" : 1.0 } \n";
  NSString *metadata = @" [ true ] ";
  NSString *valid = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:raw metadata:metadata variationUID:@"variation"
      policy:@"on_next_activate"]]];
  QONRemoteConfigV2Envelope *envelope = [self parseWireBody:valid];
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"only"].rawData, [self utf8Data:raw]);
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"only"].metadataData, [self utf8Data:metadata]);

  NSArray<NSString *> *invalidValues = @[
    @"{\"duplicate\":1,\"duplicate\":2}",
    @"{\"a\":1,\"\\u0061\":2}",
    @"9007199254740992",
    @"1e400",
    @"\"\\uD800\"",
  ];
  for (NSString *invalid in invalidValues) {
    NSString *body = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
        [self wireItemWithRaw:invalid metadata:@"null" variationUID:@"variation"
        policy:@"on_next_activate"]]];
    XCTAssertNil([self parseWireBody:body], @"%@", invalid);
  }
}

- (void)testWireNumberValidationIsIndependentOfThreadNumericLocale {
  locale_t commaLocale = newlocale(LC_NUMERIC_MASK, "de_DE.UTF-8", NULL);
  if (!commaLocale) commaLocale = newlocale(LC_NUMERIC_MASK, "fr_FR.UTF-8", NULL);
  XCTAssertNotEqual(commaLocale, (locale_t)0);
  if (!commaLocale) return;
  locale_t previousLocale = uselocale(commaLocale);
  @try {
    NSString *validBody = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
        [self wireItemWithRaw:@"1.5" metadata:@"null" variationUID:@"variation"
        policy:@"on_next_activate"]]];
    NSString *nonFiniteBody = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
        [self wireItemWithRaw:@"1e400" metadata:@"null" variationUID:@"variation"
        policy:@"on_next_activate"]]];

    XCTAssertNotNil([self parseWireBody:validBody]);
    XCTAssertNil([self parseWireBody:nonFiniteBody]);
  } @finally {
    uselocale(previousLocale);
    freelocale(commaLocale);
  }
}

- (void)testWireParserEnforcesUTF8DepthPerValueAggregateAndExactFieldBounds {
  QONRemoteConfigV2EnvelopeParser *parser = [QONRemoteConfigV2EnvelopeParser new];
  NSMutableData *oversizedBody = [NSMutableData dataWithLength:QONRemoteConfigV2MaximumEnvelopeBytes + 1];
  XCTAssertNil([parser parseBody:oversizedBody strongETag:@"invalid" expectation:[self wireExpectation]]);
  NSMutableData *invalidUTF8 = [[self utf8Data:[self wireBodyWithValues:[NSString stringWithFormat:
      @"\"only\":%@", [self wireItemWithRaw:@"true" metadata:@"null"
      variationUID:@"variation" policy:@"on_next_activate"]]]] mutableCopy];
  uint8_t *bytes = invalidUTF8.mutableBytes;
  bytes[invalidUTF8.length / 2] = 0xff;
  XCTAssertNil([parser parseBody:invalidUTF8 strongETag:[self strongETagForBody:invalidUTF8]
      expectation:[self wireExpectation]]);

  NSString *validBody = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:@"true" metadata:@"null" variationUID:@"variation"
      policy:@"on_next_activate"]]];
  NSArray<NSString *> *invalidBodies = @[
    [validBody stringByReplacingOccurrencesOfString:@"\"raw\":true,"
        withString:@"\"unknown\":0,\"raw\":true,"],
    [validBody stringByReplacingOccurrencesOfString:@"\"raw\":true,"
        withString:@"\"raw\":false,\"raw\":true,"],
    [validBody stringByReplacingOccurrencesOfString:@"\"raw\":true," withString:@""],
    [validBody stringByReplacingOccurrencesOfString:@"\"release_number\":7"
        withString:@"\"release_number\":9007199254740992"],
    [validBody stringByReplacingOccurrencesOfString:@"\"variation_uid\":\"variation\""
        withString:[NSString stringWithFormat:@"\"variation_uid\":\"%@\"",
        [@"v" stringByPaddingToLength:37 withString:@"v" startingAtIndex:0]]],
  ];
  for (NSString *invalidBody in invalidBodies) XCTAssertNil([self parseWireBody:invalidBody]);

  NSMutableString *tooDeep = [NSMutableString new];
  for (NSUInteger index = 0; index < 65; index++) [tooDeep appendString:@"["];
  [tooDeep appendString:@"null"];
  for (NSUInteger index = 0; index < 65; index++) [tooDeep appendString:@"]"];
  NSString *deepBody = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:tooDeep metadata:@"null" variationUID:@"variation"
      policy:@"on_next_activate"]]];
  XCTAssertNil([self parseWireBody:deepBody]);

  NSString *exactRaw = [@"true" stringByPaddingToLength:QONRemoteConfigV2MaximumRawValueBytes
      withString:@" " startingAtIndex:0];
  NSString *exactMetadata = [@"null" stringByPaddingToLength:QONRemoteConfigV2MaximumMetadataBytes
      withString:@" " startingAtIndex:0];
  NSString *exactBody = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:exactRaw metadata:exactMetadata variationUID:@"variation"
      policy:@"on_next_activate"]]];
  XCTAssertNotNil([self parseWireBody:exactBody]);
  NSString *oversizedRawItem = [self wireItemWithRaw:[exactRaw stringByAppendingString:@" "]
      metadata:exactMetadata variationUID:@"variation" policy:@"on_next_activate"];
  NSString *oversizedRawBody = [self wireBodyWithValues:
      [NSString stringWithFormat:@"\"only\":%@", oversizedRawItem]];
  XCTAssertNil([self parseWireBody:oversizedRawBody]);
  NSString *oversizedMetadataItem = [self wireItemWithRaw:exactRaw
      metadata:[exactMetadata stringByAppendingString:@" "] variationUID:@"variation"
      policy:@"on_next_activate"];
  NSString *oversizedMetadataBody = [self wireBodyWithValues:
      [NSString stringWithFormat:@"\"only\":%@", oversizedMetadataItem]];
  XCTAssertNil([self parseWireBody:oversizedMetadataBody]);

  NSMutableArray<NSString *> *items = [NSMutableArray new];
  NSString *nearMaximumRaw = [NSString stringWithFormat:@"\"%@\"",
      [@"x" stringByPaddingToLength:QONRemoteConfigV2MaximumRawValueBytes - 2
      withString:@"x" startingAtIndex:0]];
  for (NSUInteger index = 0; index < 65; index++) {
    [items addObject:[NSString stringWithFormat:@"\"key-%lu\":%@", (unsigned long)index,
        [self wireItemWithRaw:nearMaximumRaw metadata:@"null"
        variationUID:[NSString stringWithFormat:@"v-%lu", (unsigned long)index]
        policy:@"on_next_activate"]]];
  }
  XCTAssertNil([self parseWireBody:[self wireBodyWithValues:[items componentsJoinedByString:@","]]]);
}

- (void)testWireEnvelopeAndReleaseOwnImmutableCopiesOfCallerBytes {
  NSMutableData *body = [[[self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:@"true" metadata:@"null" variationUID:@"variation"
      policy:@"on_next_activate"]]] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  NSData *original = [body copy];
  QONRemoteConfigV2Envelope *envelope = [[QONRemoteConfigV2EnvelopeParser new]
      parseBody:body strongETag:[self strongETagForBody:body] expectation:[self wireExpectation]];
  [body resetBytesInRange:NSMakeRange(0, body.length)];

  XCTAssertEqualObjects(envelope.canonicalBody, original);
  XCTAssertEqualObjects(envelope.snapshotRelease.canonicalBody, original);
  XCTAssertEqualObjects(envelope.snapshotRelease.entries[@"only"].rawData, [self utf8Data:@"true"]);
}

- (QONRemoteConfigV2Manager *)managerWithStorage:(id<QNLocalStorage>)storage
                                         decoder:(id<QONRemoteConfigV2EnvelopeDecoding>)decoder {
  return [self managerWithStorage:storage decoder:decoder
      callbackExecutor:dispatch_get_main_queue()];
}

- (QONRemoteConfigV2Manager *)managerWithStorage:(id<QNLocalStorage>)storage
                                         decoder:(id<QONRemoteConfigV2EnvelopeDecoding>)decoder
                                callbackExecutor:(dispatch_queue_t)callbackExecutor {
  return [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:nil fallbackProjectKey:nil fallbackEnvironment:nil
      envelopeDecoder:decoder callbackExecutor:callbackExecutor];
}

- (void)testAdmissionTokenIsManagerScopeExpectationAndLatestRequestBound {
  QONRemoteConfigV2Manager *first = [self managerWithStorage:[QNInMemoryStorage new]
      decoder:[QONRemoteConfigV2EnvelopeParser new]];
  QONRemoteConfigV2Manager *second = [self managerWithStorage:[QNInMemoryStorage new]
      decoder:[QONRemoteConfigV2EnvelopeParser new]];
  QONRemoteConfigV2Scope *scope = [self wireScope:@"user"];
  [first setScope:scope];
  [second setScope:scope];
  QONRemoteConfigV2AdmissionToken *old = [first beginAdmissionForScope:scope
      expectation:[self wireExpectation]];
  QONRemoteConfigV2AdmissionToken *latest = [first beginAdmissionForScope:scope
      expectation:[self wireExpectation]];
  NSString *bodyString = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:@"1" metadata:@"null" variationUID:@"variation"
      policy:@"on_next_activate"]]];
  NSData *body = [self utf8Data:bodyString];
  NSString *etag = [self strongETagForBody:body];

  XCTAssertEqual([first admitBody:body strongETag:etag admissionToken:old],
                 QONRemoteConfigV2TransitionStatusRejected);
  XCTAssertEqual([second admitBody:body strongETag:etag admissionToken:latest],
                 QONRemoteConfigV2TransitionStatusRejected);
  XCTAssertEqual([first admitBody:body strongETag:etag admissionToken:latest],
                 QONRemoteConfigV2TransitionStatusAccepted);
  XCTAssertEqualObjects(first.lastFetchedSnapshot.releaseUID, @"release");

  QONRemoteConfigV2AdmissionToken *contextToken = [first beginAdmissionForScope:scope
      expectation:[[QONRemoteConfigV2EnvelopeExpectation alloc] initWithProjectID:42
          environmentUID:@"env-production"
          contextFingerprint:[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]]];
  XCTAssertEqual([first admitBody:body strongETag:etag admissionToken:contextToken],
                 QONRemoteConfigV2TransitionStatusRejected);

  [first setScope:[self wireScope:@"user-b"]];
  [first setScope:scope];
  XCTAssertEqual([first admitBody:body strongETag:etag admissionToken:latest],
                 QONRemoteConfigV2TransitionStatusRejected);
}

- (void)testAdmissionRechecksLatestTokenAfterBlockingParseBeforeAnyPersistence {
  QONRemoteConfigBlockingEnvelopeDecoder *decoder = [QONRemoteConfigBlockingEnvelopeDecoder new];
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  QONRemoteConfigV2Manager *manager = [self managerWithStorage:storage decoder:decoder];
  QONRemoteConfigV2Scope *scope = [self wireScope:@"user"];
  [manager setScope:scope];
  QONRemoteConfigV2AdmissionToken *superseded = [manager beginAdmissionForScope:scope
      expectation:[self wireExpectation]];
  NSString *bodyString = [self wireBodyWithValues:[NSString stringWithFormat:@"\"only\":%@",
      [self wireItemWithRaw:@"1" metadata:@"null" variationUID:@"variation"
      policy:@"immediate"]]];
  NSData *body = [self utf8Data:bodyString];
  __block QONRemoteConfigV2TransitionStatus result = QONRemoteConfigV2TransitionStatusAccepted;
  dispatch_group_t group = dispatch_group_create();
  dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    result = [manager admitBody:body strongETag:[self strongETagForBody:body]
        admissionToken:superseded];
  });
  XCTAssertEqual(dispatch_semaphore_wait(decoder.started,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);

  XCTAssertNotNil([manager beginAdmissionForScope:scope expectation:[self wireExpectation]]);
  dispatch_semaphore_signal(decoder.resume);
  XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);

  XCTAssertEqual(result, QONRemoteConfigV2TransitionStatusRejected);
  XCTAssertNil(manager.lastFetchedSnapshot);
  XCTAssertNil(storage.objects[QONRemoteConfigV2StorageKey]);
}

- (void)testCompleteWireAdmissionTombstonesMissingActiveKeysAndAllowsEqualReleaseContextRerender {
  QONRemoteConfigV2Manager *manager = [self managerWithStorage:[QNInMemoryStorage new]
      decoder:[QONRemoteConfigV2EnvelopeParser new]];
  QONRemoteConfigV2Scope *scope = [self wireScope:@"user"];
  [manager setScope:scope];
  [manager acceptFetchedRelease:[self release:@"initial" number:6 values:@{
    @"kept": @"1", @"removed": @"2",
  } immediate:NO] forScope:scope];
  XCTAssertTrue([manager activate]);

  NSString *firstBodyString = [self wireBodyWithValues:[NSString stringWithFormat:@"\"kept\":%@",
      [self wireItemWithRaw:@"3" metadata:@"null" variationUID:@"variation-a"
      policy:@"on_next_activate"]]];
  NSData *firstBody = [self utf8Data:firstBodyString];
  QONRemoteConfigV2AdmissionToken *firstToken = [manager beginAdmissionForScope:scope
      expectation:[self wireExpectation]];
  XCTAssertEqual([manager admitBody:firstBody strongETag:[self strongETagForBody:firstBody]
      admissionToken:firstToken], QONRemoteConfigV2TransitionStatusAccepted);
  XCTAssertTrue([manager activate]);
  XCTAssertNil([manager.currentSnapshot rawValueForKey:@"removed"]);

  NSString *secondBodyString = [firstBodyString
      stringByReplacingOccurrencesOfString:@"\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
      withString:@"\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\""];
  secondBodyString = [secondBodyString stringByReplacingOccurrencesOfString:@"variation-a"
      withString:@"variation-b"];
  NSData *secondBody = [self utf8Data:secondBodyString];
  QONRemoteConfigV2AdmissionToken *secondToken = [manager beginAdmissionForScope:scope
      expectation:[[QONRemoteConfigV2EnvelopeExpectation alloc] initWithProjectID:42
          environmentUID:@"env-production"
          contextFingerprint:[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]]];
  XCTAssertEqual([manager admitBody:secondBody strongETag:[self strongETagForBody:secondBody]
      admissionToken:secondToken], QONRemoteConfigV2TransitionStatusAccepted);
  XCTAssertEqualObjects(manager.lastFetchedSnapshot.releaseUID, @"release");
  XCTAssertTrue([manager activate]);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"release");

  NSString *lowerBodyString = [secondBodyString stringByReplacingOccurrencesOfString:
      @"\"release_number\":7" withString:@"\"release_number\":6"];
  NSData *lowerBody = [self utf8Data:lowerBodyString];
  QONRemoteConfigV2AdmissionToken *lowerToken = [manager beginAdmissionForScope:scope
      expectation:[[QONRemoteConfigV2EnvelopeExpectation alloc] initWithProjectID:42
          environmentUID:@"env-production"
          contextFingerprint:[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]]];
  XCTAssertEqual([manager admitBody:lowerBody strongETag:[self strongETagForBody:lowerBody]
      admissionToken:lowerToken], QONRemoteConfigV2TransitionStatusRejected);
  XCTAssertEqual(manager.lastFetchedSnapshot.releaseNumber, 7);
}

- (void)testCommittedImmediateDeliverySurvivesNewerAdmissionThatNeverCommits {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self wireScope:@"user"];
  [manager setScope:scope];
  __block NSMutableArray<NSString *> *observed = [NSMutableArray new];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    if ([update.snapshot.releaseUID isEqualToString:@"blocking"]) {
      [manager acceptFetchedRelease:[self release:@"release" number:2
          values:@{@"key": @"2"} immediate:YES] forScope:scope];
      XCTAssertNotNil([manager beginAdmissionForScope:scope expectation:[self wireExpectation]]);
    }
  }];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    [observed addObject:update.snapshot.releaseUID];
  }];
  [manager acceptFetchedRelease:[self release:@"blocking" number:1
      values:@{@"key": @"1"} immediate:YES] forScope:scope];

  XCTAssertEqualObjects(observed, (@[@"blocking", @"release"]));
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"release");
}

- (NSData *)utf8Data:(NSString *)string {
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertNotNil(data);
  return data ?: [NSData data];
}

- (QONRemoteConfigV2Release *)release:(NSString *)uid
                               number:(NSInteger)number
                               values:(NSDictionary<NSString *, NSString *> *)values
                            immediate:(BOOL)immediate {
  NSMutableDictionary *entries = [NSMutableDictionary new];
  [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *json, __unused BOOL *stop) {
    entries[key] = [[QONRemoteConfigV2Entry alloc]
        initWithKey:key rawData:[self utf8Data:json]
        variationUID:[NSString stringWithFormat:@"%@-%@", uid, key]
        applyPolicy:immediate ? QONRemoteConfigApplyPolicyImmediate : QONRemoteConfigApplyPolicyOnNextActivate
        metadata:@{@"release": uid}];
  }];
  return [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:uid releaseNumber:number
      manifestContentHash:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:entries];
}

- (QONRemoteConfigV2Manager *)managerWithFallback:(QONRemoteConfigV2Release *)fallback {
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc]
      initWithLocalStorage:[QNInMemoryStorage new]];
  return [[QONRemoteConfigV2Manager alloc] initWithStore:store
      fallbackRelease:fallback fallbackProjectKey:@"project" fallbackEnvironment:@"production"];
}

- (QONRemoteConfigV2Scope *)scope:(NSString *)userID {
  return [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:userID];
}

- (QONRemoteConfigV2Release *)release:(NSString *)uid
                               number:(NSInteger)number
                                  raw:(NSString *)raw
                            variation:(NSString *)variation
                               policy:(QONRemoteConfigApplyPolicy)policy
                             metadata:(id)metadata {
  QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:[self utf8Data:raw]
      variationUID:variation applyPolicy:policy metadata:metadata];
  NSString *hashCharacter = [NSString stringWithFormat:@"%lx", (long)(number % 16)];
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:uid releaseNumber:number
      manifestContentHash:[hashCharacter stringByPaddingToLength:64
          withString:hashCharacter startingAtIndex:0]
      entries:@{@"key": entry}];
}

- (void)testCandidateWaitsForActivateAndOldSnapshotsNeverMutate {
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{@"key": @"\"fallback\""} immediate:NO];
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:fallback];
  [manager setScope:[self scope:@"user-a"]];
  [manager acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"\"one\""} immediate:NO]
                        forScope:[self scope:@"user-a"]];

  XCTAssertEqual([manager.currentSnapshot rawValueForKey:@"key"].source, QONRemoteConfigValueSourceFallback);
  XCTAssertTrue([manager activate]);
  QONRemoteConfigSnapshot *oldSnapshot = manager.currentSnapshot;
  XCTAssertEqualObjects([oldSnapshot rawValueForKey:@"key"].value, @"one");

  [manager acceptFetchedRelease:[self release:@"two" number:2 values:@{@"key": @"\"two\""} immediate:NO]
                        forScope:[self scope:@"user-a"]];
  XCTAssertEqualObjects([manager.currentSnapshot rawValueForKey:@"key"].value, @"one");
  XCTAssertEqualObjects(manager.lastFetchedSnapshot.releaseUID, @"two");
  XCTAssertTrue([manager activate]);
  XCTAssertFalse([manager activate]);
  XCTAssertEqualObjects([manager.currentSnapshot rawValueForKey:@"key"].value, @"two");
  XCTAssertEqualObjects([oldSnapshot rawValueForKey:@"key"].value, @"one");
}

- (void)testIdentityBoundaryNeverShowsPreviousUsersActiveSnapshot {
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{@"key": @"\"fallback\""} immediate:NO];
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:fallback];
  [manager setScope:[self scope:@"user-a"]];
  [manager acceptFetchedRelease:[self release:@"user-a-release" number:1 values:@{@"key": @"\"private-a\""} immediate:NO]
                        forScope:[self scope:@"user-a"]];
  XCTAssertTrue([manager activate]);

  [manager setScope:[self scope:@"user-b"]];
  XCTAssertEqualObjects([manager.currentSnapshot rawValueForKey:@"key"].value, @"fallback");
  XCTAssertEqual([manager.currentSnapshot rawValueForKey:@"key"].source, QONRemoteConfigValueSourceFallback);

  [manager setScope:[self scope:@"user-a"]];
  XCTAssertEqualObjects([manager.currentSnapshot rawValueForKey:@"key"].value, @"private-a");
}

- (void)testLateCandidateFromPreviousIdentityIsDiscarded {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:[self release:@"bundle" number:1
      values:@{@"key": @"\"fallback\""} immediate:NO]];
  QONRemoteConfigV2Scope *userA = [self scope:@"user-a"];
  [manager setScope:userA];
  [manager setScope:[self scope:@"user-b"]];

  [manager acceptFetchedRelease:[self release:@"late-a" number:2
      values:@{@"key": @"\"private-a\""} immediate:YES] forScope:userA];

  XCTAssertEqualObjects([manager.currentSnapshot rawValueForKey:@"key"].value, @"fallback");
  XCTAssertNil(manager.lastFetchedSnapshot);
}

- (void)testOlderResponseCannotReplaceFresherCandidateForSameScope {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  [manager acceptFetchedRelease:[self release:@"newer" number:2 values:@{@"key": @"2"} immediate:NO]
                        forScope:scope];
  [manager acceptFetchedRelease:[self release:@"older" number:1 values:@{@"key": @"1"} immediate:YES]
                        forScope:scope];

  XCTAssertEqualObjects(manager.lastFetchedSnapshot.releaseUID, @"newer");
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
  XCTAssertTrue([manager activate]);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"newer");
}

- (void)testCandidateActiveAndPreviousSurviveRestartAsOneScopedState {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  QONRemoteConfigV2Manager *first = [[QONRemoteConfigV2Manager alloc]
      initWithStore:store fallbackRelease:nil fallbackProjectKey:nil fallbackEnvironment:nil];
  [first setScope:scope];
  [first acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"1"} immediate:NO]
                       forScope:scope];
  XCTAssertTrue([first activate]);
  [first acceptFetchedRelease:[self release:@"two" number:2 values:@{@"key": @"2"} immediate:NO]
                       forScope:scope];
  XCTAssertTrue([first activate]);
  [first acceptFetchedRelease:[self release:@"three" number:3 values:@{@"key": @"3"} immediate:NO]
                       forScope:scope];

  QONRemoteConfigV2Manager *restarted = [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:nil fallbackProjectKey:nil fallbackEnvironment:nil];
  [restarted setScope:scope];

  XCTAssertEqualObjects(restarted.currentSnapshot.releaseUID, @"two");
  XCTAssertEqualObjects(restarted.lastFetchedSnapshot.releaseUID, @"three");
  XCTAssertFalse([restarted.currentSnapshot.allKeys containsObject:@"unknown"]);
  XCTAssertTrue([restarted activate]);
  XCTAssertEqualObjects(restarted.currentSnapshot.releaseUID, @"three");
}

- (void)testImmediateEntryActivatesEntireReleaseAndPublishesOneAtomicDiff {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:[self release:@"bundle" number:1 values:@{
    @"a": @"0", @"b": @"0",
  } immediate:NO]];
  [manager setScope:[self scope:@"user"]];
  XCTAssertTrue([manager activate]);

  __block QONRemoteConfigUpdate *update = nil;
  id token = [manager addUpdateObserver:^(QONRemoteConfigUpdate *received) {
    update = received;
  }];
  QONRemoteConfigV2Entry *immediate = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"a" rawData:[self utf8Data:@"1"]
      variationUID:@"immediate-a" applyPolicy:QONRemoteConfigApplyPolicyImmediate
      metadata:@{@"release": @"immediate"}];
  QONRemoteConfigV2Entry *onNextActivate = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"b" rawData:[self utf8Data:@"2"]
      variationUID:@"immediate-b" applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate
      metadata:@{@"release": @"immediate"}];
  QONRemoteConfigV2Release *mixedPolicyRelease = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"immediate" releaseNumber:2
      manifestContentHash:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:@{@"a": immediate, @"b": onNextActivate}];
  [manager acceptFetchedRelease:mixedPolicyRelease forScope:[self scope:@"user"]];

  XCTAssertNotNil(token);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"immediate");
  XCTAssertEqualObjects(update.changedKeys, ([NSSet setWithArray:@[@"a", @"b"]]));
  XCTAssertEqualObjects(update.metadataByKey[@"a"], (@{@"release": @"immediate"}));
  XCTAssertEqualObjects([update.snapshot rawValueForKey:@"a"].value, @1);
  XCTAssertEqualObjects([update.snapshot rawValueForKey:@"b"].value, @2);
}

- (void)testFailedCandidatePersistenceDoesNotChangeLastFetchedState {
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:[self release:@"bundle" number:1 values:@{@"key": @"0"} immediate:NO]
      fallbackProjectKey:@"project" fallbackEnvironment:@"production"];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  storage.failWrites = YES;

  [manager acceptFetchedRelease:[self release:@"candidate" number:2 values:@{@"key": @"1"} immediate:NO]
                        forScope:scope];

  XCTAssertNil(manager.lastFetchedSnapshot);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"bundle");
}

- (void)testFailedExplicitActivationPreservesCandidateAndActiveUntilRetryCommits {
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:[self release:@"bundle" number:1 values:@{@"key": @"0"} immediate:NO]
      fallbackProjectKey:@"project" fallbackEnvironment:@"production"];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  [manager acceptFetchedRelease:[self release:@"candidate" number:2 values:@{@"key": @"1"} immediate:NO]
                        forScope:scope];
  storage.failWrites = YES;

  XCTAssertFalse([manager activate]);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"bundle");
  XCTAssertEqualObjects(manager.lastFetchedSnapshot.releaseUID, @"candidate");

  storage.failWrites = NO;
  XCTAssertTrue([manager activate]);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"candidate");
}

- (void)testFailedImmediatePersistencePublishesNoUpdateAndPreservesActiveState {
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:[self release:@"bundle" number:1 values:@{@"key": @"0"} immediate:NO]
      fallbackProjectKey:@"project" fallbackEnvironment:@"production"];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  XCTAssertTrue([manager activate]);
  __block NSUInteger updateCount = 0;
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) { updateCount += 1; }];
  storage.throwOnWrite = YES;

  [manager acceptFetchedRelease:[self release:@"immediate-failure" number:2
      values:@{@"key": @"1"} immediate:YES] forScope:scope];

  XCTAssertEqual(updateCount, 0u);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"bundle");
  XCTAssertNil(manager.lastFetchedSnapshot);
}

- (void)testLastFetchedAfterActivationUsesActualPreviousActiveDecodeTier {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  [manager acceptFetchedRelease:[self release:@"one" number:1
      values:@{@"key": @"{\"value\":1}"} immediate:NO] forScope:scope];
  XCTAssertTrue([manager activate]);
  [manager acceptFetchedRelease:[self release:@"two" number:2
      values:@{@"key": @"\"wrong-shape\""} immediate:NO] forScope:scope];
  XCTAssertTrue([manager activate]);

  QONRemoteConfigValue *resolved = [manager.lastFetchedSnapshot valueForKey:@"key"
      decoder:^id(NSData *data, NSError **error) {
    id value = [NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingFragmentsAllowed error:error];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
  }];

  XCTAssertEqual(resolved.source, QONRemoteConfigValueSourceCache);
  XCTAssertEqualObjects(resolved.value, (@{@"value": @1}));
}

- (void)testActivationWithNoEffectiveDiffReturnsFalseAndPublishesNoCallback {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  __block NSUInteger callbackCount = 0;
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) { callbackCount += 1; }];
  [manager acceptFetchedRelease:[self release:@"empty" number:1 values:@{} immediate:NO]
                        forScope:scope];

  XCTAssertFalse([manager activate]);
  XCTAssertEqual(callbackCount, 0u);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"empty");
}

- (void)testEffectiveDiffIncludesRawVariationPolicyAndMetadataButNotReleaseIdentityAlone {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  __block NSMutableArray<NSSet<NSString *> *> *diffs = [NSMutableArray new];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    [diffs addObject:update.changedKeys];
  }];
  [manager acceptFetchedRelease:[self release:@"one" number:1 raw:@"1" variation:@"v1"
      policy:QONRemoteConfigApplyPolicyOnNextActivate metadata:@{@"m": @1}] forScope:scope];
  XCTAssertTrue([manager activate]);
  [manager acceptFetchedRelease:[self release:@"two" number:2 raw:@"1" variation:@"v2"
      policy:QONRemoteConfigApplyPolicyOnNextActivate metadata:@{@"m": @1}] forScope:scope];
  XCTAssertTrue([manager activate]);
  [manager acceptFetchedRelease:[self release:@"three" number:3 raw:@"1" variation:@"v2"
      policy:QONRemoteConfigApplyPolicyImmediate metadata:@{@"m": @1}] forScope:scope];
  [manager acceptFetchedRelease:[self release:@"four" number:4 raw:@"1" variation:@"v2"
      policy:QONRemoteConfigApplyPolicyImmediate metadata:@{@"m": @2}] forScope:scope];
  [manager acceptFetchedRelease:[self release:@"five" number:5 raw:@"2" variation:@"v2"
      policy:QONRemoteConfigApplyPolicyImmediate metadata:@{@"m": @2}] forScope:scope];
  [manager acceptFetchedRelease:[self release:@"six" number:6 raw:@"2" variation:@"v2"
      policy:QONRemoteConfigApplyPolicyImmediate metadata:@{@"m": @2}] forScope:scope];

  XCTAssertEqual(diffs.count, 5u);
  for (NSSet<NSString *> *diff in diffs) XCTAssertEqualObjects(diff, [NSSet setWithObject:@"key"]);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"six");
}

- (void)testBundledFallbackIsBoundToProjectAndEnvironment {
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1
      values:@{@"key": @"\"fallback\""} immediate:NO];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc]
      initWithLocalStorage:[QNInMemoryStorage new]];
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:store fallbackRelease:fallback fallbackProjectKey:@"project"
      fallbackEnvironment:@"production"];

  [manager setScope:[[QONRemoteConfigV2Scope alloc] initWithProjectKey:@"project"
      environment:@"sandbox" canonicalUserID:@"user"]];
  XCTAssertNil([manager.currentSnapshot rawValueForKey:@"key"]);
  [manager setScope:[[QONRemoteConfigV2Scope alloc] initWithProjectKey:@"other-project"
      environment:@"production" canonicalUserID:@"user"]];
  XCTAssertNil([manager.currentSnapshot rawValueForKey:@"key"]);
  [manager setScope:[self scope:@"user"]];
  XCTAssertEqualObjects([manager.currentSnapshot rawValueForKey:@"key"].value, @"fallback");
}

- (void)testTransientScopeLoadFailureCannotOverwriteDurableActiveAndSameScopeRetries {
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  QONRemoteConfigV2Release *active = [self release:@"private" number:1
      values:@{@"key": @"\"private\""} immediate:NO];
  QONRemoteConfigV2State *durableState = [[QONRemoteConfigV2State alloc]
      initWithCandidate:active active:active previous:nil didActivate:YES];
  XCTAssertNotNil(durableState);
  XCTAssertTrue([store saveState:durableState forScope:scope]);
  storage.readsToFail = 2;
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:store fallbackRelease:nil fallbackProjectKey:nil fallbackEnvironment:nil];

  [manager setScope:scope];
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
  XCTAssertFalse([manager activate]);
  XCTAssertEqualObjects(storage.objects[QONRemoteConfigV2StorageKey][@"scopes"][0]
      [@"state"][@"active"][@"uid"], @"private");

  [manager setScope:scope];
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"private");
}

- (void)testReentrantObserverPreservesCommitOrderForEveryObserver {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  __block NSMutableArray<NSString *> *observed = [NSMutableArray new];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    if ([update.snapshot.releaseUID isEqualToString:@"one"]) {
      [manager acceptFetchedRelease:[self release:@"two" number:2 values:@{@"key": @"2"}
          immediate:YES] forScope:scope];
    }
  }];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    [observed addObject:update.snapshot.releaseUID];
  }];

  [manager acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"1"}
      immediate:YES] forScope:scope];

  XCTAssertEqualObjects(observed, (@[@"one", @"two"]));
}

- (void)testObserverCallbacksAlwaysRunOnMainExecutor {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  XCTestExpectation *delivered = [self expectationWithDescription:@"main callback"];
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) {
    XCTAssertTrue(NSThread.isMainThread);
    [delivered fulfill];
  }];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"1"}
        immediate:YES] forScope:scope];
  });

  [self waitForExpectations:@[delivered] timeout:2];
}

- (void)testScopeFenceDropsOldDeliveryQueuedBeforeObserverInvocation {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *oldScope = [self scope:@"user-a"];
  [manager setScope:oldScope];
  dispatch_semaphore_t commitReturned = dispatch_semaphore_create(0);
  __block NSUInteger oldCallbacks = 0;
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) { oldCallbacks += 1; }];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"private" number:1
        values:@{@"key": @"1"} immediate:YES] forScope:oldScope];
    dispatch_semaphore_signal(commitReturned);
  });
  XCTAssertEqual(dispatch_semaphore_wait(commitReturned,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);

  [manager setScope:[self scope:@"user-b"]];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.05];
  [NSRunLoop.currentRunLoop runUntilDate:deadline];

  XCTAssertEqual(oldCallbacks, 0u);
}

- (void)testReentrantScopeChangeFencesRemainingObserversAndQueuedPrivateDelivery {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  __block NSMutableArray<NSString *> *observed = [NSMutableArray new];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    if ([update.snapshot.releaseUID isEqualToString:@"one"]) {
      [manager setScope:nil];
      [manager acceptFetchedRelease:[self release:@"two" number:2
          values:@{@"key": @"2"} immediate:YES] forScope:scope];
    }
  }];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    [observed addObject:update.snapshot.releaseUID];
  }];

  [manager acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"1"}
      immediate:YES] forScope:scope];

  XCTAssertEqualObjects(observed, (@[]));
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
}

- (void)testConcurrentCommitDuringSlowDeliveryPreservesFIFOOrder {
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  dispatch_queue_t callbacks = dispatch_queue_create(
      "io.qonversion.remote-config-v2-tests-fifo", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2Manager *manager = [self managerWithStorage:storage
      decoder:[QONRemoteConfigV2EnvelopeParser new] callbackExecutor:callbacks];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  dispatch_semaphore_t firstDeliveryStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseFirstDelivery = dispatch_semaphore_create(0);
  dispatch_semaphore_t secondCommitFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t bothDeliveriesObserved = dispatch_semaphore_create(0);
  __block NSMutableArray<NSString *> *observed = [NSMutableArray new];
  storage.writeObserver = ^(NSDictionary *root) {
    NSArray *scopes = root[@"scopes"];
    NSDictionary *record = scopes.lastObject;
    NSString *activeUID = record[@"state"][@"active"][@"uid"];
    if ([activeUID isEqualToString:@"two"]) dispatch_semaphore_signal(secondCommitFinished);
  };
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    if ([update.snapshot.releaseUID isEqualToString:@"one"]) {
      dispatch_semaphore_signal(firstDeliveryStarted);
      dispatch_semaphore_wait(releaseFirstDelivery,
                              dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
  }];
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    @synchronized (observed) {
      [observed addObject:update.snapshot.releaseUID];
      if (observed.count == 2) dispatch_semaphore_signal(bothDeliveriesObserved);
    }
  }];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"1"}
        immediate:YES] forScope:scope];
  });
  XCTAssertEqual(dispatch_semaphore_wait(firstDeliveryStarted,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"two" number:2 values:@{@"key": @"2"}
        immediate:YES] forScope:scope];
  });
  XCTAssertEqual(dispatch_semaphore_wait(secondCommitFinished,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
  dispatch_semaphore_signal(releaseFirstDelivery);

  XCTAssertEqual(dispatch_semaphore_wait(bothDeliveriesObserved,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);
  @synchronized (observed) { XCTAssertEqualObjects(observed, (@[@"one", @"two"])); }
}

- (void)testScopeChangeCompletesDuringInFlightDeliveryAndSuppressesRemainingOldScopeCallbacks {
  dispatch_queue_t callbacks = dispatch_queue_create(
      "io.qonversion.remote-config-v2-tests-scope", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2Manager *manager = [self managerWithStorage:[QNInMemoryStorage new]
      decoder:[QONRemoteConfigV2EnvelopeParser new] callbackExecutor:callbacks];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  dispatch_semaphore_t firstObserverStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseFirstObserver = dispatch_semaphore_create(0);
  dispatch_semaphore_t logoutFinished = dispatch_semaphore_create(0);
  dispatch_semaphore_t deliveryFinished = dispatch_semaphore_create(0);
  __block BOOL callbackAfterLogout = NO;
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) {
    dispatch_semaphore_signal(firstObserverStarted);
    dispatch_semaphore_wait(releaseFirstObserver,
                            dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
  }];
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) {
    if (dispatch_semaphore_wait(logoutFinished, DISPATCH_TIME_NOW) == 0) callbackAfterLogout = YES;
  }];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"private" number:1
        values:@{@"key": @"\"private\""} immediate:YES] forScope:scope];
    dispatch_semaphore_signal(deliveryFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(firstObserverStarted,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager setScope:nil];
    dispatch_semaphore_signal(logoutFinished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(logoutFinished,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);
  dispatch_semaphore_signal(releaseFirstObserver);
  XCTAssertEqual(dispatch_semaphore_wait(deliveryFinished,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);

  XCTAssertFalse(callbackAfterLogout);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
}

- (void)testBackgroundObserverMainSyncCannotDeadlockMainScopeFenceOrLeakOldScopeDelivery {
  XCTAssertTrue(NSThread.isMainThread);
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  dispatch_queue_t callbacks = dispatch_queue_create(
      "io.qonversion.remote-config-v2-tests-main-hop", DISPATCH_QUEUE_SERIAL);
  QONRemoteConfigV2Manager *manager = [self managerWithStorage:storage
      decoder:[QONRemoteConfigV2EnvelopeParser new] callbackExecutor:callbacks];
  QONRemoteConfigV2Scope *oldScope = [self scope:@"user-a"];
  QONRemoteConfigV2Scope *newScope = [self scope:@"user-b"];
  [manager setScope:oldScope];
  dispatch_semaphore_t firstObserverStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t secondAcceptanceReturned = dispatch_semaphore_create(0);
  dispatch_semaphore_t callbackQueueDrained = dispatch_semaphore_create(0);
  __block NSUInteger firstObserverInvocations = 0;
  __block NSUInteger remainingObserverInvocations = 0;
  __block BOOL mainHopDidRun = NO;
  [manager addUpdateObserver:^(QONRemoteConfigUpdate *update) {
    firstObserverInvocations += 1;
    if ([update.snapshot.releaseUID isEqualToString:@"one"]) {
      dispatch_semaphore_signal(firstObserverStarted);
      dispatch_sync(dispatch_get_main_queue(), ^{ mainHopDidRun = YES; });
    }
  }];
  [manager addUpdateObserver:^(__unused QONRemoteConfigUpdate *update) {
    remainingObserverInvocations += 1;
  }];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"one" number:1 values:@{@"key": @"1"}
        immediate:YES] forScope:oldScope];
  });
  XCTAssertEqual(dispatch_semaphore_wait(firstObserverStarted,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager acceptFetchedRelease:[self release:@"two" number:2 values:@{@"key": @"2"}
        immediate:YES] forScope:oldScope];
    dispatch_semaphore_signal(secondAcceptanceReturned);
  });
  XCTAssertEqual(dispatch_semaphore_wait(secondAcceptanceReturned,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0L);

  [manager setScope:newScope];
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
  dispatch_async(callbacks, ^{ dispatch_semaphore_signal(callbackQueueDrained); });
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  BOOL didDrainCallbackQueue = NO;
  while (!didDrainCallbackQueue && deadline.timeIntervalSinceNow > 0) {
    didDrainCallbackQueue = dispatch_semaphore_wait(
        callbackQueueDrained, DISPATCH_TIME_NOW) == 0;
    if (didDrainCallbackQueue) break;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
  }

  XCTAssertTrue(didDrainCallbackQueue);
  XCTAssertTrue(mainHopDidRun);
  XCTAssertEqual(firstObserverInvocations, 1u);
  XCTAssertEqual(remainingObserverInvocations, 0u);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
}

@end
