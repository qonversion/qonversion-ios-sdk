//
//  QONRemoteConfigV2ManagerTests.m
//  QonversionTests
//

#import <XCTest/XCTest.h>

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

@interface QONRemoteConfigV2ManagerTests : XCTestCase
@end

@implementation QONRemoteConfigV2ManagerTests

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

- (void)testConcurrentCommitDuringSlowDeliveryPreservesFIFOOrder {
  QONRemoteConfigFailingStorage *storage = [QONRemoteConfigFailingStorage new];
  QONRemoteConfigV2Manager *manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:[[QONRemoteConfigV2Store alloc] initWithLocalStorage:storage]
      fallbackRelease:nil fallbackProjectKey:nil fallbackEnvironment:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  dispatch_semaphore_t firstDeliveryStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseFirstDelivery = dispatch_semaphore_create(0);
  dispatch_semaphore_t secondCommitFinished = dispatch_semaphore_create(0);
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
    @synchronized (observed) { [observed addObject:update.snapshot.releaseUID]; }
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

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  while (observed.count < 2 && deadline.timeIntervalSinceNow > 0) {
    [NSThread sleepForTimeInterval:0.005];
  }
  XCTAssertEqualObjects(observed, (@[@"one", @"two"]));
}

- (void)testScopeChangeWaitsForInFlightDeliveryAndSuppressesRemainingOldScopeCallbacks {
  QONRemoteConfigV2Manager *manager = [self managerWithFallback:nil];
  QONRemoteConfigV2Scope *scope = [self scope:@"user"];
  [manager setScope:scope];
  dispatch_semaphore_t firstObserverStarted = dispatch_semaphore_create(0);
  dispatch_semaphore_t releaseFirstObserver = dispatch_semaphore_create(0);
  dispatch_semaphore_t logoutFinished = dispatch_semaphore_create(0);
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
  });
  XCTAssertEqual(dispatch_semaphore_wait(firstObserverStarted,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [manager setScope:nil];
    dispatch_semaphore_signal(logoutFinished);
  });
  XCTAssertNotEqual(dispatch_semaphore_wait(logoutFinished,
      dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)), 0);
  dispatch_semaphore_signal(releaseFirstObserver);
  XCTAssertEqual(dispatch_semaphore_wait(logoutFinished,
      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);

  XCTAssertFalse(callbackAfterLogout);
  XCTAssertEqualObjects(manager.currentSnapshot.releaseUID, @"");
}

@end
