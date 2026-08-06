//
//  QONRemoteConfigSnapshotTests.m
//  QonversionTests
//

#import <XCTest/XCTest.h>

#import "QONRemoteConfigSnapshot.h"
#import "QONRemoteConfigSnapshot+Protected.h"
#import "QONRemoteConfigV2Models.h"

@interface QONRemoteConfigSnapshotTests : XCTestCase
@end

@implementation QONRemoteConfigSnapshotTests

- (NSString *)validHash {
  return [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
}

- (NSData *)utf8Data:(NSString *)string {
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertNotNil(data);
  return data ?: [NSData data];
}

- (QONRemoteConfigV2Release *)release:(NSString *)uid
                               number:(NSInteger)number
                               values:(NSDictionary<NSString *, NSString *> *)values {
  NSMutableDictionary *entries = [NSMutableDictionary new];
  [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *json, __unused BOOL *stop) {
    entries[key] = [[QONRemoteConfigV2Entry alloc]
        initWithKey:key
            rawData:[self utf8Data:json]
       variationUID:[NSString stringWithFormat:@"%@-%@", uid, key]
        applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate
            metadata:nil];
  }];
  return [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:uid
           releaseNumber:number
     manifestContentHash:self.validHash
                 entries:entries];
}

- (void)testTypedResolutionFallsBackPerKeyWhileRawResolutionKeepsServerValue {
  QONRemoteConfigV2Release *primary = [self release:@"release-2" number:2 values:@{
    @"paywall": @"\"not-a-paywall-object\"",
    @"title": @"\"server-title\"",
  }];
  QONRemoteConfigV2Release *previous = [self release:@"release-1" number:1 values:@{
    @"paywall": @"{\"title\":\"cached\"}",
    @"title": @"\"cached-title\"",
  }];
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{
    @"paywall": @"{\"title\":\"fallback\"}",
    @"only_bundle": @"true",
  }];
  QONRemoteConfigSnapshot *snapshot = [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:primary previousRelease:previous fallbackRelease:fallback];

  QONRemoteConfigValue *typed = [snapshot valueForKey:@"paywall" decoder:^id(NSData *data, NSError **error) {
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:error];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
  }];
  XCTAssertEqual(typed.source, QONRemoteConfigValueSourceCache);
  XCTAssertEqualObjects(typed.value, (@{@"title": @"cached"}));

  QONRemoteConfigValue *raw = [snapshot rawValueForKey:@"paywall"];
  XCTAssertEqual(raw.source, QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects(raw.value, @"not-a-paywall-object");

  QONRemoteConfigValue *bundleOnly = [snapshot rawValueForKey:@"only_bundle"];
  XCTAssertEqual(bundleOnly.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(bundleOnly.value, @YES);
}

- (void)testDecoderErrorFallsBackFromCurrentToPreviousEvenWhenDecoderReturnsValue {
  QONRemoteConfigV2Release *primary = [self release:@"release-2" number:2 values:@{
    @"key": @"\"current\"",
  }];
  QONRemoteConfigV2Release *previous = [self release:@"release-1" number:1 values:@{
    @"key": @"\"previous\"",
  }];
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{
    @"key": @"\"bundle\"",
  }];
  QONRemoteConfigSnapshot *snapshot = [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:primary previousRelease:previous fallbackRelease:fallback];

  QONRemoteConfigValue *typed = [snapshot valueForKey:@"key" decoder:^id(NSData *data,
                                                                             NSError **error) {
    id value = [NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingFragmentsAllowed error:nil];
    if ([value isEqual:@"current"]) {
      *error = [NSError errorWithDomain:@"QONRemoteConfigSnapshotTests" code:1 userInfo:nil];
    }
    return value;
  }];

  XCTAssertEqual(typed.source, QONRemoteConfigValueSourceCache);
  XCTAssertEqualObjects(typed.value, @"previous");
  QONRemoteConfigValue *raw = [snapshot rawValueForKey:@"key"];
  XCTAssertEqual(raw.source, QONRemoteConfigValueSourceServer);
  XCTAssertEqualObjects(raw.value, @"current");
}

- (void)testDecoderErrorsFallBackFromCurrentAndPreviousToBundleEvenWhenReturningValues {
  QONRemoteConfigV2Release *primary = [self release:@"release-2" number:2 values:@{
    @"key": @"\"current\"",
  }];
  QONRemoteConfigV2Release *previous = [self release:@"release-1" number:1 values:@{
    @"key": @"\"previous\"",
  }];
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{
    @"key": @"\"bundle\"",
  }];
  QONRemoteConfigSnapshot *snapshot = [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:primary previousRelease:previous fallbackRelease:fallback];

  QONRemoteConfigValue *typed = [snapshot valueForKey:@"key" decoder:^id(NSData *data,
                                                                             NSError **error) {
    id value = [NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingFragmentsAllowed error:nil];
    if (![value isEqual:@"bundle"]) {
      *error = [NSError errorWithDomain:@"QONRemoteConfigSnapshotTests" code:2 userInfo:nil];
    }
    return value;
  }];

  XCTAssertEqual(typed.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(typed.value, @"bundle");
}

- (void)testSnapshotAndReturnedValuesDoNotObserveCallerMutation {
  NSMutableData *raw = [[self utf8Data:@"{\"enabled\":true}"] mutableCopy];
  QONRemoteConfigV2Entry *entry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"feature" rawData:raw variationUID:@"variation"
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:@{@"reset": @YES}];
  QONRemoteConfigV2Release *release = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:self.validHash
      entries:@{@"feature": entry}];
  QONRemoteConfigSnapshot *snapshot = [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:release previousRelease:nil fallbackRelease:nil];

  [raw replaceBytesInRange:NSMakeRange(0, raw.length) withBytes:"null" length:4];
  NSMutableDictionary *first = [[snapshot rawValueForKey:@"feature"].value mutableCopy];
  first[@"enabled"] = @NO;

  XCTAssertEqualObjects([snapshot rawValueForKey:@"feature"].value, (@{@"enabled": @YES}));
  XCTAssertEqualObjects([snapshot metadataForKey:@"feature"], (@{@"reset": @YES}));
}

- (void)testMissingPrimaryKeyDoesNotResurrectPreviousValue {
  QONRemoteConfigV2Release *primary = [self release:@"release-2" number:2 values:@{}];
  QONRemoteConfigV2Release *previous = [self release:@"release-1" number:1 values:@{
    @"removed": @"\"stale\"",
    @"fallback_key": @"\"stale-cache\"",
  }];
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{
    @"fallback_key": @"\"bundled\"",
  }];
  QONRemoteConfigSnapshot *snapshot = [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:primary previousRelease:previous fallbackRelease:fallback];

  XCTAssertNil([snapshot rawValueForKey:@"removed"]);
  XCTAssertNil([snapshot valueForKey:@"removed" decoder:^id(NSData *data, NSError **error) {
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:error];
  }]);
  XCTAssertFalse([snapshot.allKeys containsObject:@"removed"]);
  XCTAssertNil([snapshot metadataForKey:@"removed"]);

  QONRemoteConfigValue *fallbackValue = [snapshot rawValueForKey:@"fallback_key"];
  XCTAssertEqual(fallbackValue.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(fallbackValue.value, @"bundled");
}

- (void)testExplicitTombstoneSkipsPreviousAndResolvesDirectlyToBundle {
  QONRemoteConfigV2Entry *tombstone = [[QONRemoteConfigV2Entry alloc]
      initWithTombstoneKey:@"removed"];
  QONRemoteConfigV2Release *primary = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release-2" releaseNumber:2 manifestContentHash:self.validHash
      entries:@{@"removed": tombstone}];
  QONRemoteConfigV2Release *previous = [self release:@"release-1" number:1 values:@{
    @"removed": @"\"private-old\"",
  }];
  QONRemoteConfigV2Release *fallback = [self release:@"bundle" number:1 values:@{
    @"removed": @"\"safe-default\"",
  }];
  QONRemoteConfigSnapshot *snapshot = [[QONRemoteConfigSnapshot alloc]
      initWithPrimaryRelease:primary previousRelease:previous fallbackRelease:fallback];

  QONRemoteConfigValue *raw = [snapshot rawValueForKey:@"removed"];
  QONRemoteConfigValue *typed = [snapshot valueForKey:@"removed" decoder:^id(NSData *data,
                                                                               NSError **error) {
    return [NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingFragmentsAllowed error:error];
  }];

  XCTAssertTrue(tombstone.isTombstone);
  XCTAssertEqual(raw.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(raw.value, @"safe-default");
  XCTAssertEqual(typed.source, QONRemoteConfigValueSourceFallback);
  XCTAssertEqualObjects(typed.value, @"safe-default");
}

- (void)testModelBoundsAcceptExactLimitsAndRejectPlusOne {
  NSMutableString *exactRawString = [NSMutableString stringWithString:@"\""];
  [exactRawString appendString:[@"x" stringByPaddingToLength:QONRemoteConfigV2MaximumRawValueBytes - 2
                                                  withString:@"x" startingAtIndex:0]];
  [exactRawString appendString:@"\""];
  NSData *exactRaw = [self utf8Data:exactRawString];
  NSData *oversizedRaw = [self utf8Data:[exactRawString stringByAppendingString:@" "]];
  QONRemoteConfigV2Entry *boundaryEntry = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:exactRaw variationUID:@"variation"
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];

  XCTAssertNotNil(boundaryEntry);
  XCTAssertNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:oversizedRaw variationUID:@"variation"
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil]);

  NSString *metadataJSON = [NSString stringWithFormat:@"\"%@\"",
      [@"m" stringByPaddingToLength:QONRemoteConfigV2MaximumMetadataBytes - 2
                         withString:@"m" startingAtIndex:0]];
  id boundaryMetadata = [NSJSONSerialization JSONObjectWithData:
      [self utf8Data:metadataJSON]
      options:NSJSONReadingFragmentsAllowed error:nil];
  QONRemoteConfigV2Entry *metadataBoundary = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"metadata" rawData:[self utf8Data:@"1"]
      variationUID:@"variation" applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate
      metadata:boundaryMetadata];
  XCTAssertNotNil(metadataBoundary);
  XCTAssertNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:@"metadata" rawData:[self utf8Data:@"1"]
      variationUID:@"variation" applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate
      metadata:[boundaryMetadata stringByAppendingString:@"m"]]);

  NSMutableDictionary *rawOnlyMaximumEntries = [NSMutableDictionary new];
  for (NSUInteger index = 0; index < QONRemoteConfigV2MaximumTotalValueBytes /
                                      QONRemoteConfigV2MaximumRawValueBytes; index++) {
    NSString *key = [NSString stringWithFormat:@"key-%lu", (unsigned long)index];
    rawOnlyMaximumEntries[key] = [[QONRemoteConfigV2Entry alloc]
        initWithKey:key rawData:exactRaw variationUID:@"variation"
        applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  }
  XCTAssertNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:self.validHash
      entries:rawOnlyMaximumEntries], @"keys and identifiers are part of the release byte budget");

  NSMutableDictionary *exactEntries = [NSMutableDictionary new];
  NSUInteger usedBytes = [@"release" lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
      [self.validHash lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  for (NSUInteger index = 0; index < 63; index++) {
    NSString *key = [NSString stringWithFormat:@"key-%02lu", (unsigned long)index];
    NSString *variation = @"variation";
    exactEntries[key] = [[QONRemoteConfigV2Entry alloc]
        initWithKey:key rawData:exactRaw variationUID:variation
        applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
    usedBytes += [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
        [variation lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + exactRaw.length;
  }
  NSString *lastKey = @"key-63";
  NSString *lastVariation = @"variation";
  NSUInteger lastRawBytes = QONRemoteConfigV2MaximumTotalValueBytes - usedBytes -
      [lastKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding] -
      [lastVariation lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  NSString *lastRawJSON = [NSString stringWithFormat:@"\"%@\"",
      [@"z" stringByPaddingToLength:lastRawBytes - 2 withString:@"z" startingAtIndex:0]];
  exactEntries[lastKey] = [[QONRemoteConfigV2Entry alloc]
      initWithKey:lastKey rawData:[self utf8Data:lastRawJSON]
      variationUID:lastVariation applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  QONRemoteConfigV2Release *boundaryRelease = [[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:self.validHash
      entries:exactEntries];
  XCTAssertNotNil(boundaryRelease);

  NSMutableDictionary *oversizedEntries = [exactEntries mutableCopy];
  QONRemoteConfigV2Entry *extra = [[QONRemoteConfigV2Entry alloc] initWithTombstoneKey:@"extra"];
  oversizedEntries[@"extra"] = extra;
  XCTAssertNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:self.validHash
      entries:oversizedEntries]);

  NSString *maximumUID = [@"u" stringByPaddingToLength:QONRemoteConfigV2MaximumUIDCodePoints
                                            withString:@"u" startingAtIndex:0];
  XCTAssertNotNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:maximumUID releaseNumber:1 manifestContentHash:self.validHash entries:@{}]);
  XCTAssertNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:[maximumUID stringByAppendingString:@"u"] releaseNumber:1
      manifestContentHash:self.validHash entries:@{}]);
  XCTAssertNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:@"not-a-sha256" entries:@{}]);

  NSMutableDictionary *maximumCountEntries = [NSMutableDictionary new];
  for (NSUInteger index = 0; index < QONRemoteConfigV2MaximumEntryCount; index++) {
    NSString *key = [NSString stringWithFormat:@"count-%04lu", (unsigned long)index];
    maximumCountEntries[key] = [[QONRemoteConfigV2Entry alloc]
        initWithKey:key rawData:[self utf8Data:@"0"]
        variationUID:@"variation" applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  }
  XCTAssertNotNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:self.validHash
      entries:maximumCountEntries]);
  maximumCountEntries[@"count-extra"] = [[QONRemoteConfigV2Entry alloc]
      initWithKey:@"count-extra" rawData:[self utf8Data:@"0"]
      variationUID:@"variation" applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  XCTAssertNil([[QONRemoteConfigV2Release alloc]
      initWithReleaseUID:@"release" releaseNumber:1 manifestContentHash:self.validHash
      entries:maximumCountEntries]);

  NSString *maximumKey = [@"k" stringByPaddingToLength:QONRemoteConfigV2MaximumKeyBytes
                                            withString:@"k" startingAtIndex:0];
  XCTAssertNotNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:maximumKey rawData:[self utf8Data:@"0"]
      variationUID:maximumUID applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil]);
  XCTAssertNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:[maximumKey stringByAppendingString:@"k"]
      rawData:[self utf8Data:@"0"]
      variationUID:maximumUID applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil]);
  XCTAssertNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:[self utf8Data:@"0"]
      variationUID:[maximumUID stringByAppendingString:@"u"]
      applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil]);

  NSString *maximumScopeComponent = [@"s" stringByPaddingToLength:QONRemoteConfigV2MaximumScopeComponentBytes
                                                        withString:@"s" startingAtIndex:0];
  XCTAssertNotNil([[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:maximumScopeComponent environment:maximumUID
      canonicalUserID:maximumScopeComponent]);
  XCTAssertNil([[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:[maximumScopeComponent stringByAppendingString:@"s"]
      environment:maximumUID canonicalUserID:maximumScopeComponent]);
  XCTAssertNil([[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:maximumScopeComponent environment:[maximumUID stringByAppendingString:@"u"]
      canonicalUserID:maximumScopeComponent]);

  NSMutableString *unicodeProject = [NSMutableString new];
  for (NSUInteger index = 0; index < 128; index++) [unicodeProject appendString:@"é"];
  NSMutableString *unicodeEnvironment = [NSMutableString new];
  for (NSUInteger index = 0; index < 36; index++) [unicodeEnvironment appendString:@"😀"];
  QONRemoteConfigV2Scope *unicodeBoundary = [[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:unicodeProject environment:unicodeEnvironment
      canonicalUserID:maximumScopeComponent];
  XCTAssertNotNil(unicodeBoundary);
  XCTAssertEqual([unicodeProject lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                 QONRemoteConfigV2MaximumScopeComponentBytes);
  XCTAssertNil([[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:[unicodeProject stringByAppendingString:@"é"]
      environment:unicodeEnvironment canonicalUserID:maximumScopeComponent]);
  XCTAssertNil([[QONRemoteConfigV2Scope alloc]
      initWithProjectKey:unicodeProject
      environment:[unicodeEnvironment stringByAppendingString:@"😀"]
      canonicalUserID:maximumScopeComponent]);
}

- (void)testNetworkEntriesUseSamePortableJSONProfileAsBundledDefaults {
  QONRemoteConfigV2Entry *(^entryWithRaw)(NSData *) = ^QONRemoteConfigV2Entry *(NSData *raw) {
    return [[QONRemoteConfigV2Entry alloc]
        initWithKey:@"key" rawData:raw variationUID:@"variation"
        applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil];
  };

  XCTAssertNil(entryWithRaw([self utf8Data:@"{\"duplicate\":1,\"duplicate\":2}"]));
  const uint8_t invalidUTF8[] = {0x22, 0xff, 0x22};
  XCTAssertNil(entryWithRaw([NSData dataWithBytes:invalidUTF8 length:sizeof(invalidUTF8)]));
  XCTAssertNotNil(entryWithRaw([self utf8Data:@"9007199254740991"]));
  XCTAssertNil(entryWithRaw([self utf8Data:@"9007199254740992"]));

  NSMutableString *depth64 = [NSMutableString new];
  for (NSUInteger index = 0; index < 64; index++) [depth64 appendString:@"["];
  [depth64 appendString:@"null"];
  for (NSUInteger index = 0; index < 64; index++) [depth64 appendString:@"]"];
  XCTAssertNotNil(entryWithRaw([self utf8Data:depth64]));
  NSMutableString *depth65 = [depth64 mutableCopy];
  [depth65 insertString:@"[" atIndex:0];
  [depth65 appendString:@"]"];
  XCTAssertNil(entryWithRaw([self utf8Data:depth65]));

  XCTAssertNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:[self utf8Data:@"0"]
      variationUID:@"variation" applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate
      metadata:@9007199254740992LL]);

  unichar unpairedSurrogate = 0xD800;
  NSString *invalidUID = [NSString stringWithCharacters:&unpairedSurrogate length:1];
  XCTAssertNil([[QONRemoteConfigV2Entry alloc]
      initWithKey:@"key" rawData:[self utf8Data:@"0"]
      variationUID:invalidUID applyPolicy:QONRemoteConfigApplyPolicyOnNextActivate metadata:nil]);
}

- (void)testStateRejectsImpossibleHistoryRelationships {
  QONRemoteConfigV2Release *one = [self release:@"one" number:1 values:@{@"key": @"1"}];
  QONRemoteConfigV2Release *two = [self release:@"two" number:2 values:@{@"key": @"2"}];
  QONRemoteConfigV2Release *twoConflict = [self release:@"two-conflict" number:2
      values:@{@"key": @"3"}];

  XCTAssertNil([[QONRemoteConfigV2State alloc]
      initWithCandidate:nil active:nil previous:one didActivate:YES]);
  XCTAssertNil([[QONRemoteConfigV2State alloc]
      initWithCandidate:nil active:one previous:nil didActivate:NO]);
  XCTAssertNil([[QONRemoteConfigV2State alloc]
      initWithCandidate:one active:two previous:nil didActivate:YES]);
  XCTAssertNil([[QONRemoteConfigV2State alloc]
      initWithCandidate:twoConflict active:two previous:one didActivate:YES]);
  XCTAssertNil([[QONRemoteConfigV2State alloc]
      initWithCandidate:nil active:one previous:two didActivate:YES]);
  XCTAssertNotNil([[QONRemoteConfigV2State alloc]
      initWithCandidate:two active:two previous:one didActivate:YES]);
}

@end
