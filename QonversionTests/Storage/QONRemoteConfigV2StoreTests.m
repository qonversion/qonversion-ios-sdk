//
//  QONRemoteConfigV2StoreTests.m
//  QonversionTests
//

#import <XCTest/XCTest.h>

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

- (QONRemoteConfigV2Release *)largeRelease:(NSString *)uid fill:(unichar)fill {
  NSMutableDictionary *entries = [NSMutableDictionary new];
  for (NSUInteger index = 0; index < 44; index++) {
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

- (void)testCorruptCandidateIsSalvagedWithoutErasingActivePreviousOrOtherScopes {
  QNInMemoryStorage *storage = [QNInMemoryStorage new];
  QONRemoteConfigV2Store *store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage];
  QONRemoteConfigV2Scope *userA = [self scopeForUser:@"user-a"];
  QONRemoteConfigV2Scope *userB = [self scopeForUser:@"user-b"];
  QONRemoteConfigV2State *stateA = [[QONRemoteConfigV2State alloc]
      initWithCandidate:[self release:@"three" number:3 value:@"3"]
      active:[self release:@"two" number:2 value:@"2"]
      previous:[self release:@"one" number:1 value:@"1"] didActivate:YES];
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

  QONRemoteConfigV2State *salvaged = [store stateForScope:userA];

  XCTAssertNil(salvaged.candidate);
  XCTAssertEqualObjects(salvaged.active.releaseUID, @"two");
  XCTAssertEqualObjects(salvaged.previous.releaseUID, @"one");
  XCTAssertEqualObjects([store stateForScope:userB].candidate.releaseUID, @"other");
  QONRemoteConfigV2Store *restarted = [[QONRemoteConfigV2Store alloc]
      initWithLocalStorage:storage];
  XCTAssertNil([restarted stateForScope:userA].candidate);
  XCTAssertEqualObjects([restarted stateForScope:userA].active.releaseUID, @"two");
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
  for (NSUInteger index = 0; index < 12; index++) {
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

  XCTAssertLessThanOrEqual(archive.length, 32 * 1024 * 1024);
  QONRemoteConfigV2Scope *oldestScope = scopes.firstObject;
  QONRemoteConfigV2Scope *newestScope = scopes.lastObject;
  XCTAssertNotNil(oldestScope);
  XCTAssertNotNil(newestScope);
  XCTAssertNil([store stateForScope:oldestScope]);
  XCTAssertEqualObjects([store stateForScope:newestScope].candidate.releaseUID, @"large-11");
}

@end
