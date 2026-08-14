//
//  QONRemoteConfigV2StoreTests.m
//  QonversionTests
//

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>

#import "QNInMemoryStorage.h"
#import "QONRemoteConfigV2Models.h"
#import "QONRemoteConfigV2Store.h"

@interface QONRemoteConfigThrowingReadStorage : NSObject <QNLocalStorage>
@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, assign) NSUInteger readsToFail;
@property (nonatomic, assign) BOOL failReadAfterStore;
@end

@implementation QONRemoteConfigThrowingReadStorage
- (instancetype)init { self = [super init]; if (self) _objects = [NSMutableDictionary new]; return self; }
- (void)storeObject:(id)object forKey:(NSString *)key {
  self.objects[key] = object;
  if (self.failReadAfterStore) {
    self.failReadAfterStore = NO;
    self.readsToFail = 1;
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

@interface QONRemoteConfigV2StoreTests : XCTestCase
@end

@implementation QONRemoteConfigV2StoreTests

- (NSData *)utf8Data:(NSString *)string {
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertNotNil(data);
  return data ?: [NSData data];
}

- (QONRemoteConfigV2Release *)release:(NSString *)uid value:(NSString *)value {
  return [self release:uid number:1 value:value];
}

- (QONRemoteConfigV2Release *)release:(NSString *)uid
                               number:(NSInteger)number
                                value:(NSString *)value {
  QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:[self utf8Data:value]
      variationUID:[uid stringByAppendingString:@"-variation"]
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  return [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:uid releaseNumber:number
      manifestContentHash:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:@{@"key": entry}];
}

- (id)mutablePropertyListCopy:(id)object {
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:object
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
  return [NSPropertyListSerialization propertyListWithData:data
      options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
}

- (QONRemoteConfigV2Scope *)scopeForUser:(NSString *)userID {
  return [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:userID];
}

- (NSString *)strongETagForBody:(NSData *)body {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(body.bytes, (CC_LONG)body.length, digest);
  NSMutableString *hex = [NSMutableString stringWithString:@"\""];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  [hex appendString:@"\""];
  return [hex copy];
}

- (void)refreshDigestForMutableState:(NSMutableDictionary *)state {
  NSMutableDictionary *payload = [state mutableCopy];
  [payload removeObjectForKey:@"state_digest"];
  NSData *data = [NSJSONSerialization dataWithJSONObject:payload
      options:NSJSONWritingSortedKeys error:nil];
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  state[@"state_digest"] = hex;
}

- (QONRemoteConfigV2Release *)wireReleaseWithUID:(NSString *)releaseUID
                                           number:(NSInteger)releaseNumber
                                          ordinal:(int64_t)ordinal
                                              raw:(NSString *)raw
                                         metadata:(NSString *)metadata {
  NSString *context = [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
  NSString *bodyString = [NSString stringWithFormat:
      @"{\"schema_version\":1,\"project_id\":42,\"environment_uid\":\"production\","
       "\"release_uid\":\"%@\",\"release_number\":%ld,\"manifest_content_hash\":"
       "\"05b3abf2579a5eb66403cd78be557fd860633a1fe2103c7642030defe32c657f\","
       "\"complete_key_set\":true,\"context_fingerprint\":\"%@\",\"values\":{"
       "\"key\":{\"raw\":%@,\"variation_uid\":\"variation\","
       "\"apply_policy\":\"on_next_activate\",\"metadata\":%@}}}",
      releaseUID, (long)releaseNumber, context, raw, metadata];
  NSData *body = [self utf8Data:bodyString];
  QONRemoteConfigV2EnvelopeExpectation *expectation = [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:42 environmentUID:@"production" contextFingerprint:context];
  QONRemoteConfigV2Envelope *envelope = [[QONRemoteConfigV2EnvelopeParser new]
      parseBody:body strongETag:[self strongETagForBody:body] expectation:expectation];
  XCTAssertNotNil(envelope);
  return [envelope.snapshotRelease releaseBySettingAdmissionOrdinal:ordinal];
}

- (QONRemoteConfigV2Release *)largeRelease:(NSString *)uid fill:(unichar)fill {
  NSMutableDictionary *entries = [NSMutableDictionary new];
  for (NSUInteger index = 0; index < 61; index++) {
    NSString *prefix = [NSString stringWithFormat:@"%C-%@-%02lu", fill, uid,
        (unsigned long)index];
    NSMutableString *json = [NSMutableString stringWithString:@"\""];
    [json appendString:prefix];
    [json appendString:[@"x" stringByPaddingToLength:64 * 1024 - prefix.length - 2
        withString:[NSString stringWithCharacters:&fill length:1] startingAtIndex:0]];
    [json appendString:@"\""];
    NSString *key = [NSString stringWithFormat:@"key-%02lu", (unsigned long)index];
    NSString *variation = [NSString stringWithFormat:@"v-%02lu", (unsigned long)index];
    entries[key] = [[QONRemoteConfigV2Entry alloc]
        initWithKey:key rawData:[self utf8Data:json]
        variationUID:variation applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  }
  return [[QONRemoteConfigV2Release alloc] initWithReleaseUID:uid releaseNumber:1
      manifestContentHash:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:entries];
}

- (QONRemoteConfigV2Release *)wireReleaseWithOrdinal:(int64_t)ordinal {
  return [self wireReleaseWithUID:@"wire" number:7 ordinal:ordinal
      raw:@" { \"nested\" : 1 } " metadata:@" { \"reset\" : true } "];
}

- (QONRemoteConfigV2Release *)maximumAggregateWireReleaseWithOrdinal:(int64_t)ordinal {
  NSString *releaseUID = @"maximum-wire";
  NSString *manifestHash = @"05b3abf2579a5eb66403cd78be557fd860633a1fe2103c7642030defe32c657f";
  NSString *context = [@"c" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0];
  NSUInteger remaining = QONRemoteConfigV2MaximumTotalValueBytes -
      [releaseUID lengthOfBytesUsingEncoding:NSUTF8StringEncoding] -
      [manifestHash lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  NSMutableArray<NSString *> *items = [NSMutableArray new];
  for (NSUInteger index = 0; remaining > 0; index++) {
    NSString *key = [NSString stringWithFormat:@"key-%02lu", (unsigned long)index];
    NSString *variation = [NSString stringWithFormat:@"v-%02lu", (unsigned long)index];
    NSUInteger fixedBytes = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
        [variation lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 4;
    XCTAssertGreaterThan(remaining, fixedBytes + 1);
    NSUInteger rawBytes = MIN(QONRemoteConfigV2MaximumRawValueBytes, remaining - fixedBytes);
    NSString *raw = [NSString stringWithFormat:@"\"%@\"",
        [@"x" stringByPaddingToLength:rawBytes - 2 withString:@"x" startingAtIndex:0]];
    [items addObject:[NSString stringWithFormat:
        @"\"%@\":{\"raw\":%@,\"variation_uid\":\"%@\","
         "\"apply_policy\":\"on_next_activate\",\"metadata\":null}",
        key, raw, variation]];
    remaining -= fixedBytes + rawBytes;
  }
  NSString *bodyString = [NSString stringWithFormat:
      @"{\"schema_version\":1,\"project_id\":42,\"environment_uid\":\"production\","
       "\"release_uid\":\"%@\",\"release_number\":7,\"manifest_content_hash\":\"%@\","
       "\"complete_key_set\":true,\"context_fingerprint\":\"%@\",\"values\":{%@}}",
      releaseUID, manifestHash, context, [items componentsJoinedByString:@","]];
  NSData *body = [self utf8Data:bodyString];
  QONRemoteConfigV2EnvelopeExpectation *expectation = [[QONRemoteConfigV2EnvelopeExpectation alloc]
      initWithProjectID:42 environmentUID:@"production" contextFingerprint:context];
  QONRemoteConfigV2Envelope *envelope = [[QONRemoteConfigV2EnvelopeParser new]
      parseBody:body strongETag:[self strongETagForBody:body] expectation:expectation];
  XCTAssertNotNil(envelope);
  return [envelope.snapshotRelease releaseBySettingAdmissionOrdinal:ordinal];
}

- (void)testWireStateRoundTripsExactBodyETagContextMetadataAndAdmissionHighWater {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Release *candidate = [self wireReleaseWithOrdinal:5];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:candidate active:nil previous:nil didActivate:NO
      latestAdmissionOrdinal:7];

  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"user"]]);
  QONRemoteConfigV2State *reloaded = [[[QONRemoteConfigV2Store alloc]
      initWithLocalStorage:storage] stateForScope:[self scopeForUser:@"user"]];

  XCTAssertEqual(reloaded.latestAdmissionOrdinal, 7);
  XCTAssertEqual(reloaded.candidate.admissionOrdinal, 5);
  XCTAssertEqual(reloaded.candidate.projectID, 42);
  XCTAssertEqualObjects(reloaded.candidate.canonicalBody, candidate.canonicalBody);
  XCTAssertEqualObjects(reloaded.candidate.strongETag, candidate.strongETag);
  XCTAssertEqualObjects(reloaded.candidate.contextFingerprint,
      [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0]);
  XCTAssertEqualObjects(reloaded.candidate.entries[@"key"].rawData,
      [self utf8Data:@" { \"nested\" : 1 } "]);
  XCTAssertEqualObjects(reloaded.candidate.entries[@"key"].metadataData,
      [self utf8Data:@" { \"reset\" : true } "]);
  NSDictionary *archive = [storage loadObjectForKey:QONRemoteConfigV2StorageKey];
  XCTAssertNotNil(archive[@"scopes"][0][@"state"][@"state_digest"]);
}

- (void)testDigestMismatchCanonicalReparseRemainsBoundToOriginalProjectExpectation {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"project-bound-user"];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
      didActivate:NO latestAdmissionOrdinal:5];
  XCTAssertTrue([store saveState:state forScope:scope]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  NSMutableDictionary *storedCandidate = archive[@"scopes"][0][@"state"][@"candidate"];
  NSData *originalBody = [[NSData alloc] initWithBase64EncodedString:
      storedCandidate[@"canonical_body"] options:0];
  NSString *bodyString = [[NSString alloc] initWithData:originalBody encoding:NSUTF8StringEncoding];
  NSData *otherProjectBody = [self utf8Data:[bodyString stringByReplacingOccurrencesOfString:
      @"\"project_id\":42" withString:@"\"project_id\":43"]];
  storedCandidate[@"canonical_body"] = [otherProjectBody base64EncodedStringWithOptions:0];
  storedCandidate[@"strong_etag"] = [self strongETagForBody:otherProjectBody];
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:scope]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testUserOnlyScopeTamperDiscardsWholeRecordBeforeCanonicalSalvage {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
      didActivate:NO latestAdmissionOrdinal:5];
  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"user-a"]]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  archive[@"scopes"][0][@"scope"][@"user"] = @"user-b";
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:[self scopeForUser:@"user-b"]]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testProjectKeyOnlyScopeTamperDiscardsWholeRecordBeforeCanonicalSalvage {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
      didActivate:NO latestAdmissionOrdinal:5];
  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"user"]]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  archive[@"scopes"][0][@"scope"][@"project"] = @"other-project";
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];
  QONRemoteConfigV2Scope *tamperedScope = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"other-project" environment:@"production" canonicalUserID:@"user"];

  XCTAssertNil([store stateForScope:tamperedScope]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testCoordinatedOuterAndInnerUserTamperStillDiscardsWholeRecord {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
      didActivate:NO latestAdmissionOrdinal:5];
  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"user-a"]]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  archive[@"scopes"][0][@"scope"][@"user"] = @"user-b";
  archive[@"scopes"][0][@"state"][@"scope_binding"][@"user"] = @"user-b";
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:[self scopeForUser:@"user-b"]]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testCoordinatedOuterAndInnerProjectTamperStillDiscardsWholeRecord {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
      didActivate:NO latestAdmissionOrdinal:5];
  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"user"]]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  archive[@"scopes"][0][@"scope"][@"project"] = @"other-project";
  archive[@"scopes"][0][@"state"][@"scope_binding"][@"project"] = @"other-project";
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];
  QONRemoteConfigV2Scope *tamperedScope = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"other-project" environment:@"production" canonicalUserID:@"user"];

  XCTAssertNil([store stateForScope:tamperedScope]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testSwappingOtherwiseValidStatesBetweenScopeRecordsDiscardsBothRecords {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *userA = [self scopeForUser:@"user-a"];
  QONRemoteConfigV2Scope *userB = [self scopeForUser:@"user-b"];
  XCTAssertTrue([store saveState:[[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"release-a" value:@"1"]
      active:nil previous:nil didActivate:NO] forScope:userA]);
  XCTAssertTrue([store saveState:[[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"release-b" value:@"2"]
      active:nil previous:nil didActivate:NO] forScope:userB]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  id firstState = archive[@"scopes"][0][@"state"];
  archive[@"scopes"][0][@"state"] = archive[@"scopes"][1][@"state"];
  archive[@"scopes"][1][@"state"] = firstState;
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:userA]);
  XCTAssertNil([store stateForScope:userB]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testDigestConsistentScalarCandidateSlotsFailClosedWithoutDynamicDispatchCrash {
  NSArray *invalidSlots = @[@"scalar", @42, NSNull.null];
  for (id invalidSlot in invalidSlots) {
    QNInMemoryStorage *storage = [QNInMemoryStorage new];
    QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc]
        initWithLocalStorage:storage];
    QONRemoteConfigV2Scope *scope = [self scopeForUser:@"scalar-user"];
    QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
        initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
        didActivate:NO latestAdmissionOrdinal:5];
    XCTAssertTrue([store saveState:state forScope:scope]);
    NSMutableDictionary *archive = [self mutablePropertyListCopy:
        [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
    NSMutableDictionary *storedState = archive[@"scopes"][0][@"state"];
    storedState[@"candidate"] = invalidSlot;
    [self refreshDigestForMutableState:storedState];
    [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

    XCTAssertNil([store stateForScope:scope], @"%@", invalidSlot);
    XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
  }
}

- (void)testDigestMismatchDiscardsWholeRecordEvenWhenCanonicalBodyIsValid {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"user"];
  QONRemoteConfigV2Release *candidate = [self wireReleaseWithOrdinal:5];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:candidate active:nil previous:nil didActivate:NO
      latestAdmissionOrdinal:5];
  XCTAssertTrue([store saveState:state forScope:scope]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  NSMutableDictionary *storedCandidate = archive[@"scopes"][0][@"state"][@"candidate"];
  NSMutableDictionary *storedEntry = storedCandidate[@"entries"][0];
  NSData *parseValidMutation = [self utf8Data:@" { \"nested\" : 2 } "];
  storedEntry[@"raw"] = [parseValidMutation base64EncodedStringWithOptions:0];
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:scope]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testMaximumAggregateThreeReleaseHistoryProvablyFitsArchiveBudget {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Release *wire = [self maximumAggregateWireReleaseWithOrdinal:3];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:wire
      active:[wire releaseBySettingAdmissionOrdinal:2]
      previous:[wire releaseBySettingAdmissionOrdinal:1]
      didActivate:YES latestAdmissionOrdinal:3];
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"maximum-user"];

  XCTAssertTrue([store saveState:state forScope:scope]);
  NSDictionary *root = [storage loadObjectForKey:QONRemoteConfigV2StorageKey];
  NSData *archive = [NSPropertyListSerialization dataWithPropertyList:root
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
  XCTAssertGreaterThan(archive.length, 32 * 1024 * 1024);
  XCTAssertLessThanOrEqual(archive.length, QONRemoteConfigV2MaximumArchiveBytes);
  QONRemoteConfigV2State *reloaded = [[[QONRemoteConfigV2Store alloc]
      initWithLocalStorage:storage] stateForScope:scope];
  XCTAssertEqual(reloaded.candidate.admissionOrdinal, 3);
  XCTAssertEqual(reloaded.active.admissionOrdinal, 2);
  XCTAssertEqual(reloaded.previous.admissionOrdinal, 1);
}

- (void)testTamperedMaximumAdmissionHighWaterDiscardsWholeRecord {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithOrdinal:5] active:nil previous:nil
      didActivate:NO latestAdmissionOrdinal:7];
  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"user"]]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  archive[@"scopes"][0][@"state"][@"latest_admission_ordinal"] = @(INT64_MAX);
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:[self scopeForUser:@"user"]]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testColdDiscardOfUnshippedSchemaOneDoesNotTouchLegacyRemoteConfigLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  NSDictionary *legacy = @{@"private": @"still-here"};
  [storage storeObject:legacy forKey:@"com.qonversion.keys.remote-config-lkg"];
  [storage storeObject:@{@"schema_version": @1, @"scopes": @[]}
                 forKey:QONRemoteConfigV2StorageKey];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];

  XCTAssertNil([store stateForScope:[self scopeForUser:@"user"]]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
  XCTAssertEqualObjects([storage loadObjectForKey:@"com.qonversion.keys.remote-config-lkg"], legacy);
}

- (void)testStoresWholeVersionedStatePerExactPrivacyScopeWithoutTouchingLegacyLKG {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  [storage storeObject:@{@"legacy": @YES} forKey:@"com.qonversion.keys.remote-config-lkg"];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *userA = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:@"user-a"];
  QONRemoteConfigV2Scope *userB = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:@"user-b"];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"candidate" number:3 value:@"1"]
                 active:[self release:@"active" number:2 value:@"2"]
               previous:[self release:@"previous" number:1 value:@"3"]
            didActivate:YES];

  XCTAssertTrue([store saveState:state forScope:userA]);
  QONRemoteConfigV2State *reloaded = [store stateForScope:userA];
  XCTAssertEqualObjects(reloaded.candidate.releaseUID, @"candidate");
  XCTAssertEqualObjects(reloaded.active.releaseUID, @"active");
  XCTAssertEqualObjects(reloaded.previous.releaseUID, @"previous");
  XCTAssertTrue(reloaded.didActivate);
  XCTAssertNil([store stateForScope:userB]);
  XCTAssertEqualObjects([storage loadObjectForKey:@"com.qonversion.keys.remote-config-lkg"], (@{@"legacy": @YES}));
}

- (void)testUnknownOrCorruptV2ArchiveFailsClosedWithoutBecomingAnotherUsersState {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  [storage storeObject:@{@"schema_version": @999, @"scopes": @[]} forKey:QONRemoteConfigV2StorageKey];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *scope = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:@"project" environment:@"production" canonicalUserID:@"user"];

  XCTAssertNil([store stateForScope:scope]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testBooleanPolicyInPersistedEntryIsRejectedInsteadOfBecomingImmediate {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  NSDictionary *entry = @{
    @"key": @"key",
    @"raw": [[self utf8Data:@"1"] base64EncodedStringWithOptions:0],
    @"variation": @"variation",
    @"policy": @YES,
    @"metadata": @"",
  };
  NSDictionary *release = @{
    @"uid": @"release",
    @"number": @1,
    @"hash": @"hash",
    @"entries": @[entry],
  };
  NSDictionary *state = @{
    @"candidate": release,
    @"active": @{},
    @"previous": @{},
    @"did_activate": @NO,
  };
  NSDictionary *scope = @{
    @"project": @"project",
    @"environment": @"production",
    @"user": @"user",
  };
  [storage storeObject:@{
    @"schema_version": @1,
    @"scopes": @[@{@"scope": scope, @"state": state}],
  } forKey:QONRemoteConfigV2StorageKey];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];

  XCTAssertNil([store stateForScope:[self scopeForUser:@"user"]]);
  XCTAssertNil([storage loadObjectForKey:QONRemoteConfigV2StorageKey]);
}

- (void)testScopeRecordsUseBoundedDeterministicLRUEviction {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"candidate" value:@"1"]
      active:nil previous:nil didActivate:NO];

  for (NSUInteger index = 0; index < QONRemoteConfigV2MaximumPersistedScopes; index++) {
    NSString *userID = [NSString stringWithFormat:@"user-%03lu", (unsigned long)index];
    XCTAssertTrue([store saveState:state forScope:[self scopeForUser:userID]]);
  }
  QONRemoteConfigV2Scope *promoted = [self scopeForUser:@"user-000"];
  XCTAssertNotNil([store stateForScope:promoted]);
  XCTAssertTrue([store saveState:state forScope:[self scopeForUser:@"newest"]]);

  XCTAssertNotNil([store stateForScope:promoted]);
  XCTAssertNil([store stateForScope:[self scopeForUser:@"user-001"]]);
  XCTAssertNotNil([store stateForScope:[self scopeForUser:@"newest"]]);
  NSDictionary *archive = [storage loadObjectForKey:QONRemoteConfigV2StorageKey];
  XCTAssertEqual([archive[@"scopes"] count], QONRemoteConfigV2MaximumPersistedScopes);
}

- (void)testAtomicFileStoreRoundTripsOneVersionedEnvelope {
  NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
      URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
  NSURL *fileURL = [directory URLByAppendingPathComponent:@"remote-config-v2.plist"];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithFileURL:fileURL];
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"user"];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"candidate" number:3 value:@"1"]
      active:[self release:@"active" number:2 value:@"2"]
      previous:[self release:@"previous" number:1 value:@"3"] didActivate:YES];

  XCTAssertTrue([store saveState:state forScope:scope]);
  XCTAssertGreaterThan([NSData dataWithContentsOfURL:fileURL].length, 0u);
  QONRemoteConfigV2Store *restarted = [[QONRemoteConfigV2Store alloc] initWithFileURL:fileURL];
  XCTAssertEqualObjects([restarted stateForScope:scope].active.releaseUID, @"active");

  [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
}

- (void)testDigestCorruptionDiscardsAffectedScopeWithoutErasingOtherScopes {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *userA = [self scopeForUser:@"user-a"];
  QONRemoteConfigV2Scope *userB = [self scopeForUser:@"user-b"];
  QONRemoteConfigV2State *stateA = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self wireReleaseWithUID:@"three" number:3 ordinal:3
          raw:@"3" metadata:@"null"]
      active:[self wireReleaseWithUID:@"two" number:2 ordinal:2 raw:@"2" metadata:@"null"]
      previous:[self wireReleaseWithUID:@"one" number:1 ordinal:1 raw:@"1" metadata:@"null"]
      didActivate:YES latestAdmissionOrdinal:3];
  QONRemoteConfigV2State *stateB = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"other" number:1 value:@"4"]
      active:nil previous:nil didActivate:NO];
  XCTAssertTrue([store saveState:stateA forScope:userA]);
  XCTAssertTrue([store saveState:stateB forScope:userB]);
  NSMutableDictionary *archive = [self mutablePropertyListCopy:
      [storage loadObjectForKey:QONRemoteConfigV2StorageKey]];
  NSMutableDictionary *candidate = archive[@"scopes"][0][@"state"][@"candidate"];
  candidate[@"uid"] = [@"x" stringByPaddingToLength:37 withString:@"x" startingAtIndex:0];
  [storage storeObject:archive forKey:QONRemoteConfigV2StorageKey];

  XCTAssertNil([store stateForScope:userA]);
  XCTAssertEqualObjects([store stateForScope:userB].candidate.releaseUID, @"other");
  QONRemoteConfigV2Store *restarted = [[QONRemoteConfigV2Store alloc]
      initWithLocalStorage:storage];
  XCTAssertNil([restarted stateForScope:userA]);
  XCTAssertEqualObjects([restarted stateForScope:userB].candidate.releaseUID, @"other");
}

- (void)testTransientReadFailureIsDistinctFromMissingAndNeverDeletesDurableState {
  QONRemoteConfigThrowingReadStorage *storage = [QONRemoteConfigThrowingReadStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"user"];
  QONRemoteConfigV2State *durableState = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"candidate" value:@"1"]
      active:nil previous:nil didActivate:NO];
  XCTAssertNotNil(durableState);
  XCTAssertTrue([store saveState:durableState forScope:scope]);
  storage.readsToFail = 1;
  QONRemoteConfigV2State *state = nil;

  XCTAssertEqual([store loadStateForScope:scope state:&state],
                 QONRemoteConfigV2StoreLoadStatusFailed);
  XCTAssertNil(state);
  XCTAssertNotNil(storage.objects[QONRemoteConfigV2StorageKey]);
  XCTAssertEqual([store loadStateForScope:scope state:&state],
                 QONRemoteConfigV2StoreLoadStatusFound);
  XCTAssertEqualObjects(state.candidate.releaseUID, @"candidate");
}

- (void)testReadBackFailureRollsBackNewlyCreatedLocalStorageArchive {
  QONRemoteConfigThrowingReadStorage *storage = [QONRemoteConfigThrowingReadStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"candidate" value:@"1"]
      active:nil previous:nil didActivate:NO];
  XCTAssertNotNil(state);
  storage.failReadAfterStore = YES;

  XCTAssertFalse([store saveState:state forScope:[self scopeForUser:@"user"]]);
  XCTAssertNil(storage.objects[QONRemoteConfigV2StorageKey]);
}

- (void)testTombstoneRoundTripsWithoutResurrectingAValuePayload {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Entry *tombstone = [[QONRemoteConfigV2Entry alloc]
      initWithTombstoneKey:@"removed"];
  QONRemoteConfigV2Release *release = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1
      manifestContentHash:[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
      entries:@{@"removed": tombstone}];
  QONRemoteConfigV2Scope *scope = [self scopeForUser:@"user"];
  QONRemoteConfigV2State *candidateState = [[QONRemoteConfigV2State alloc]
      initWithCandidate:release active:nil previous:nil didActivate:NO];
  XCTAssertNotNil(candidateState);
  XCTAssertTrue([store saveState:candidateState forScope:scope]);

  QONRemoteConfigV2Entry *reloaded = [store stateForScope:scope].candidate.entries[@"removed"];

  XCTAssertTrue(reloaded.isTombstone);
  XCTAssertNil(reloaded.rawData);
  XCTAssertNil(reloaded.variationUID);
  XCTAssertNil(reloaded.metadata);
}

- (void)testGlobalArchiveBudgetEvictsOldestAndKeepsNewestAdmittedScope {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  NSMutableArray<QONRemoteConfigV2Scope *> *scopes = [NSMutableArray new];
  for (NSUInteger index = 0; index < 14; index++) {
    @autoreleasepool {
      NSString *userID = [NSString stringWithFormat:@"large-user-%02lu", (unsigned long)index];
      NSString *releaseUID = [NSString stringWithFormat:@"large-%02lu", (unsigned long)index];
      QONRemoteConfigV2Scope *scope = [self scopeForUser:userID];
      QONRemoteConfigV2Release *release = [self largeRelease:releaseUID fill:(unichar)('A' + index)];
      QONRemoteConfigV2State *state = [[QONRemoteConfigV2State alloc]
          initWithCandidate:release active:nil previous:nil didActivate:NO];
      [scopes addObject:scope];
      XCTAssertTrue([store saveState:state forScope:scope]);
    }
  }
  NSDictionary *root = [storage loadObjectForKey:QONRemoteConfigV2StorageKey];
  NSData *archive = [NSPropertyListSerialization dataWithPropertyList:root
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];

  XCTAssertLessThanOrEqual(archive.length, QONRemoteConfigV2MaximumArchiveBytes);
  QONRemoteConfigV2Scope *oldestScope = scopes.firstObject;
  QONRemoteConfigV2Scope *newestScope = scopes.lastObject;
  XCTAssertNotNil(oldestScope);
  XCTAssertNotNil(newestScope);
  XCTAssertNil([store stateForScope:oldestScope]);
  XCTAssertEqualObjects([store stateForScope:newestScope].candidate.releaseUID, @"large-13");
}

@end
