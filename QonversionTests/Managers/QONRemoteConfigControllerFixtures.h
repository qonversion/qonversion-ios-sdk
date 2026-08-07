//
//  Shared deterministic fakes for the experimental Remote Config public surface.
//
//  The file carries implementations on purpose so the XCTest suite and the
//  headless harness can share exactly one set of fakes. Include it from a
//  single translation unit per target.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#import "QNLocalStorage.h"
#import "QONRemoteConfigController.h"
#import "QONRemoteConfigController+Protected.h"
#import "QONRemoteConfigFallbackStore.h"
#import "QONRemoteConfigV2FetchPolicyStore.h"
#import "QONRemoteConfigV2Store.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const QONRCPubProjectKey = @"project";
static NSString *const QONRCPubEnvironmentUID = @"env-production";
static NSString *const QONRCPubManifestHash =
    @"05b3abf2579a5eb66403cd78be557fd860633a1fe2103c7642030defe32c657f";
static NSString *const QONRCPubFingerprint =
    @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
static int64_t const QONRCPubProjectID = 42;

#pragma mark - Storage

@interface QONRCPubStorage : NSObject <QNLocalStorage>
@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, assign) BOOL failWrites;
@end

@implementation QONRCPubStorage
- (instancetype)init {
  self = [super init];
  if (self) _objects = [NSMutableDictionary new];
  return self;
}
- (void)storeObject:(id)object forKey:(NSString *)key {
  if (!self.failWrites) self.objects[key] = object;
}
- (id)loadObjectForKey:(NSString *)key { return self.objects[key]; }
- (void)loadObjectForKey:(NSString *)key withCompletion:(void (^)(id))completion {
  completion(self.objects[key]);
}
- (void)removeObjectForKey:(NSString *)key { [self.objects removeObjectForKey:key]; }
@end

#pragma mark - Scheduler and clock

@interface QONRCPubTask : NSObject <QONRemoteConfigV2FetchScheduledTask>
@property (nonatomic, copy, nullable) dispatch_block_t action;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation QONRCPubTask
- (void)cancel { self.cancelled = YES; }
@end

@interface QONRCPubScheduler : NSObject <QONRemoteConfigV2FetchScheduler>
@property (nonatomic, strong) NSMutableArray<QONRCPubTask *> *tasks;
- (BOOL)fireFirstPending;
@end

@implementation QONRCPubScheduler
- (instancetype)init {
  self = [super init];
  if (self) _tasks = [NSMutableArray new];
  return self;
}
- (id<QONRemoteConfigV2FetchScheduledTask>)scheduleAfterMilliseconds:(__unused int64_t)delay
                                                              action:(dispatch_block_t)action {
  QONRCPubTask *task = [QONRCPubTask new];
  task.action = action;
  [self.tasks addObject:task];
  return task;
}
- (BOOL)fireFirstPending {
  for (QONRCPubTask *task in [self.tasks copy]) {
    if (task.cancelled || !task.action) continue;
    dispatch_block_t action = task.action;
    task.action = nil;
    action();
    return YES;
  }
  return NO;
}
@end

@interface QONRCPubClock : NSObject <QONRemoteConfigV2FetchClock>
@property (nonatomic, assign) int64_t now;
@end

@implementation QONRCPubClock
- (int64_t)nowMilliseconds { return self.now; }
@end

@interface QONRCPubRandom : NSObject <QONRemoteConfigV2FetchRandom>
@end

@implementation QONRCPubRandom
- (double)nextUnitInterval { return 0.5; }
@end

#pragma mark - Transport

@interface QONRCPubResponse : NSObject
@property (nonatomic, strong, nullable) NSData *body;
@property (nonatomic, copy, nullable) NSString *strongETag;
@property (nonatomic, assign) BOOL failure;
@end

@implementation QONRCPubResponse
@end

/** Scripted transport that can also hold one request open indefinitely. */
@interface QONRCPubTransport : NSObject <QONRemoteConfigV2FetchTransport>
@property (nonatomic, strong) NSMutableArray<QONRCPubResponse *> *script;
@property (nonatomic, strong) NSMutableArray<QONRemoteConfigV2FetchRequest *> *requests;
@property (nonatomic, assign) BOOL holdNextRequest;
@property (nonatomic, copy, nullable) QONRemoteConfigV2FetchTransportCompletion heldCompletion;
- (void)enqueueBody:(NSData *)body strongETag:(NSString *)strongETag;
- (void)enqueueFailure;
- (BOOL)releaseHeldWithBody:(NSData *)body strongETag:(NSString *)strongETag;
@end

@implementation QONRCPubTransport
- (instancetype)init {
  self = [super init];
  if (self) {
    _script = [NSMutableArray new];
    _requests = [NSMutableArray new];
  }
  return self;
}
- (void)enqueueBody:(NSData *)body strongETag:(NSString *)strongETag {
  QONRCPubResponse *response = [QONRCPubResponse new];
  response.body = body;
  response.strongETag = strongETag;
  [self.script addObject:response];
}
- (void)enqueueFailure {
  QONRCPubResponse *response = [QONRCPubResponse new];
  response.failure = YES;
  [self.script addObject:response];
}
- (void)fetchRequest:(QONRemoteConfigV2FetchRequest *)request
          completion:(QONRemoteConfigV2FetchTransportCompletion)completion {
  [self.requests addObject:request];
  if (self.holdNextRequest) {
    self.holdNextRequest = NO;
    self.heldCompletion = completion;
    return;
  }
  QONRCPubResponse *scripted = self.script.firstObject;
  if (scripted) [self.script removeObjectAtIndex:0];
  if (!scripted || scripted.failure) {
    completion([QONRemoteConfigV2FetchResponse failureWithStatusCode:@(500)
                                              retryAfterMilliseconds:nil]);
    return;
  }
  completion([QONRemoteConfigV2FetchResponse successWithBody:scripted.body
                                                  strongETag:scripted.strongETag]);
}
- (BOOL)releaseHeldWithBody:(NSData *)body strongETag:(NSString *)strongETag {
  QONRemoteConfigV2FetchTransportCompletion completion = self.heldCompletion;
  if (!completion) return NO;
  self.heldCompletion = nil;
  completion([QONRemoteConfigV2FetchResponse successWithBody:body strongETag:strongETag]);
  return YES;
}
@end

#pragma mark - Wire builders

static NSData *QONRCPubUTF8(NSString *value) {
  return [value dataUsingEncoding:NSUTF8StringEncoding];
}

static BOOL QONRCPubDataEquals(NSData *_Nullable left, NSData *_Nullable right) {
  if (!left || !right || left.length != right.length) return NO;
  return memcmp(left.bytes, right.bytes, left.length) == 0;
}

static NSString *QONRCPubHexDigest(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [hex appendFormat:@"%02x", digest[index]];
  }
  return hex;
}

static NSString *QONRCPubStrongETag(NSData *body) {
  return [NSString stringWithFormat:@"\"%@\"", QONRCPubHexDigest(body)];
}

static NSString *QONRCPubItem(NSString *raw, NSString *variationUID, NSString *policy,
                              NSString *metadata) {
  return [NSString stringWithFormat:
      @"{\"raw\":%@,\"variation_uid\":\"%@\",\"apply_policy\":\"%@\",\"metadata\":%@}",
      raw, variationUID, policy, metadata];
}

static NSData *QONRCPubSnapshotBody(NSString *releaseUID, NSInteger releaseNumber,
                                    NSString *values) {
  NSString *body = [NSString stringWithFormat:
      @"{\"schema_version\":1,\"project_id\":%lld,\"environment_uid\":\"%@\","
       "\"release_uid\":\"%@\",\"release_number\":%ld,\"manifest_content_hash\":\"%@\","
       "\"complete_key_set\":true,\"context_fingerprint\":\"%@\",\"values\":{%@}}",
      (long long)QONRCPubProjectID, QONRCPubEnvironmentUID, releaseUID, (long)releaseNumber,
      QONRCPubManifestHash, QONRCPubFingerprint, values];
  return QONRCPubUTF8(body);
}

static QONRemoteConfigV2FetchBinding *QONRCPubBinding(QONRemoteConfigV2Scope *scope) {
  QONRemoteConfigV2EnvelopeExpectation *expectation =
      [[QONRemoteConfigV2EnvelopeExpectation alloc] initWithProjectID:QONRCPubProjectID
                                                      environmentUID:QONRCPubEnvironmentUID
                                                  contextFingerprint:QONRCPubFingerprint];
  return [[QONRemoteConfigV2FetchBinding alloc] initWithScope:scope expectation:expectation];
}

#pragma mark - Bundled defaults artifact

static void QONRCPubDigestPart(CC_SHA256_CTX *context, NSData *part) {
  uint64_t length = CFSwapInt64HostToBig((uint64_t)part.length);
  CC_SHA256_Update(context, &length, (CC_LONG)sizeof(length));
  CC_SHA256_Update(context, part.bytes, (CC_LONG)part.length);
}

/**
 Builds the generated-defaults artifact for a key-sorted list of
 @[key, variationUid, rawJSON] triples, digest included.
 */
static NSData *QONRCPubDefaultsArtifact(NSArray<NSArray<NSString *> *> *defaults) {
  NSString *releaseUID = @"release-bundle";
  int64_t releaseNumber = 1;
  CC_SHA256_CTX context;
  CC_SHA256_Init(&context);
  QONRCPubDigestPart(&context,
      [@"qonversion.remote-config-fallback-defaults.v1" dataUsingEncoding:NSASCIIStringEncoding]);
  QONRCPubDigestPart(&context, [@"1" dataUsingEncoding:NSASCIIStringEncoding]);
  QONRCPubDigestPart(&context,
      [[NSString stringWithFormat:@"%lld", (long long)QONRCPubProjectID]
          dataUsingEncoding:NSASCIIStringEncoding]);
  QONRCPubDigestPart(&context, QONRCPubUTF8(QONRCPubEnvironmentUID));
  QONRCPubDigestPart(&context, QONRCPubUTF8(releaseUID));
  QONRCPubDigestPart(&context,
      [[NSString stringWithFormat:@"%lld", (long long)releaseNumber]
          dataUsingEncoding:NSASCIIStringEncoding]);
  QONRCPubDigestPart(&context, [QONRCPubManifestHash dataUsingEncoding:NSASCIIStringEncoding]);
  QONRCPubDigestPart(&context,
      [[NSString stringWithFormat:@"%lu", (unsigned long)defaults.count]
          dataUsingEncoding:NSASCIIStringEncoding]);
  NSMutableArray<NSString *> *encodedEntries = [NSMutableArray new];
  for (NSArray<NSString *> *entry in defaults) {
    NSData *rawValue = QONRCPubUTF8(entry[2]);
    QONRCPubDigestPart(&context, QONRCPubUTF8(entry[0]));
    QONRCPubDigestPart(&context, QONRCPubUTF8(entry[1]));
    QONRCPubDigestPart(&context, rawValue);
    [encodedEntries addObject:[NSString stringWithFormat:
        @"{\"key\":\"%@\",\"variationUid\":\"%@\",\"valueBase64\":\"%@\"}",
        entry[0], entry[1], [rawValue base64EncodedStringWithOptions:0]]];
  }
  uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(digestBytes, &context);
  NSMutableString *digest = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
    [digest appendFormat:@"%02x", digestBytes[index]];
  }
  NSString *artifact = [NSString stringWithFormat:
      @"{\"schemaVersion\":1,\"projectId\":%lld,\"environmentUid\":\"%@\",\"releaseUid\":\"%@\","
       "\"releaseNumber\":%lld,\"manifestContentHash\":\"%@\",\"defaultsDigest\":\"%@\","
       "\"defaults\":[%@]}",
      (long long)QONRCPubProjectID, QONRCPubEnvironmentUID, releaseUID, (long long)releaseNumber,
      QONRCPubManifestHash, digest, [encodedEntries componentsJoinedByString:@","]];
  return QONRCPubUTF8(artifact);
}

static NSBundle *_Nullable QONRCPubBundleWithDefaults(NSData *artifact) {
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"%@.bundle", NSUUID.UUID.UUIDString]];
  NSFileManager *manager = NSFileManager.defaultManager;
  if (![manager createDirectoryAtPath:path withIntermediateDirectories:YES
                           attributes:nil error:nil]) {
    return nil;
  }
  NSDictionary *info = @{
    @"CFBundleIdentifier" : [NSString stringWithFormat:@"io.qonversion.test.%@",
                                                       NSUUID.UUID.UUIDString],
    @"CFBundleInfoDictionaryVersion" : @"6.0",
    @"CFBundlePackageType" : @"BNDL",
  };
  if (![info writeToFile:[path stringByAppendingPathComponent:@"Info.plist"] atomically:YES]) {
    return nil;
  }
  if (![artifact writeToFile:[path stringByAppendingPathComponent:
                                  @"qonversion_remote_config_defaults.json"]
                  atomically:YES]) {
    return nil;
  }
  return [NSBundle bundleWithPath:path];
}

#pragma mark - Assembled environment

/** One fully wired controller with every seam replaced by a deterministic fake. */
@interface QONRCPubEnvironment : NSObject
@property (nonatomic, strong) QONRemoteConfigController *controller;
@property (nonatomic, strong) QONRemoteConfigV2Manager *manager;
@property (nonatomic, strong) QONRemoteConfigV2FetchCoordinator *coordinator;
@property (nonatomic, strong) QONRCPubTransport *transport;
@property (nonatomic, strong) QONRCPubScheduler *scheduler;
@property (nonatomic, strong) QONRCPubClock *clock;
@property (nonatomic, strong) QONRCPubStorage *storage;
@property (nonatomic, strong) QONRemoteConfigV2Store *store;
@property (nonatomic, strong) QONRemoteConfigFallbackStore *fallbackStore;
@property (nonatomic, strong) dispatch_queue_t callbackExecutor;
@property (nonatomic, strong) dispatch_queue_t identityQueue;
@property (nonatomic, assign) NSUInteger readGuardAssertions;
- (void)drain;
- (void)settleIdentity;
@end

@implementation QONRCPubEnvironment
- (void)drain {
  // Deliveries are re-dispatched onto the same serial executor, so one pass is
  // not always enough to reach quiescence.
  for (NSUInteger index = 0; index < 6; index++) {
    dispatch_sync(self.callbackExecutor, ^{});
  }
}
- (void)settleIdentity {
  dispatch_sync(self.identityQueue, ^{});
  [self drain];
}
@end

/**
 Builds a dormant controller over a bundle that contains the given defaults.
 Pass nil to build one without any bundled defaults at all.
 */
static QONRCPubEnvironment *QONRCPubDormantEnvironment(
    NSArray<NSArray<NSString *> *> *_Nullable defaults) {
  QONRCPubEnvironment *environment = [QONRCPubEnvironment new];
  environment.callbackExecutor = dispatch_queue_create("io.qonversion.rc-pub-callbacks",
                                                       DISPATCH_QUEUE_SERIAL);
  environment.identityQueue = dispatch_queue_create("io.qonversion.rc-pub-identity",
                                                    DISPATCH_QUEUE_SERIAL);
  NSBundle *bundle = defaults ? QONRCPubBundleWithDefaults(QONRCPubDefaultsArtifact(defaults))
                              : [NSBundle bundleWithPath:NSTemporaryDirectory()];
  environment.fallbackStore = [[QONRemoteConfigFallbackStore alloc] initWithBundle:bundle];
  environment.controller = [[QONRemoteConfigController alloc]
      initWithFallbackStore:environment.fallbackStore
           callbackExecutor:environment.callbackExecutor];
  return environment;
}

/** Installs a real engine over fake transport, storage, clock and scheduler. */
static BOOL QONRCPubInstallEngine(QONRCPubEnvironment *environment,
                                  QONRemoteConfigV2ReadGuardBuildMode buildMode,
                                  int64_t minimumFetchIntervalMilliseconds,
                                  NSString *_Nullable canonicalUserID) {
  environment.storage = [QONRCPubStorage new];
  environment.store = [[QONRemoteConfigV2Store alloc] initWithLocalStorage:environment.storage];
  environment.transport = [QONRCPubTransport new];
  environment.scheduler = [QONRCPubScheduler new];
  environment.clock = [QONRCPubClock new];
  environment.clock.now = 1000;
  __weak QONRCPubEnvironment *weakEnvironment = environment;
  environment.manager = [[QONRemoteConfigV2Manager alloc]
      initWithStore:environment.store
      fallbackRelease:environment.fallbackStore.remoteConfigV2FallbackRelease
      fallbackProjectKey:QONRCPubProjectKey
      fallbackEnvironment:QONRCPubEnvironmentUID
      envelopeDecoder:[QONRemoteConfigV2EnvelopeParser new]
      callbackExecutor:environment.callbackExecutor
      readGuardBuildMode:buildMode
      assertionHandler:^(__unused NSString *message) {
        weakEnvironment.readGuardAssertions += 1;
      }
      telemetryHandler:nil
      scopePreloader:[[QONRemoteConfigStorePreloader alloc] initWithStore:environment.store]];
  QONRemoteConfigV2FetchPolicy *policy = [[QONRemoteConfigV2FetchPolicy alloc]
      initWithMinimumFetchIntervalMilliseconds:minimumFetchIntervalMilliseconds
      timeoutMilliseconds:nil
      initialBackoffMilliseconds:1000
      maximumBackoffMilliseconds:60000];
  environment.coordinator = [[QONRemoteConfigV2FetchCoordinator alloc]
      initWithCore:environment.manager
      transport:environment.transport
      policyStore:[[QONRemoteConfigV2FetchPolicyStore alloc]
          initWithLocalStorage:environment.storage]
      clock:environment.clock
      random:[QONRCPubRandom new]
      scheduler:environment.scheduler
      policy:policy
      callbackExecutor:environment.callbackExecutor
      policyPersistenceFailureObserver:nil];
  if (!environment.manager || !environment.coordinator) return NO;
  if (![environment.controller installEngineWithManager:environment.manager
                                            coordinator:environment.coordinator
                                             projectKey:QONRCPubProjectKey
                                            environment:QONRCPubEnvironmentUID
                                        bindingProvider:^QONRemoteConfigV2FetchBinding *(
                                            QONRemoteConfigV2Scope *scope) {
                                          return QONRCPubBinding(scope);
                                        }
                                              scopeSink:nil
                                              scheduler:environment.scheduler
                                          identityQueue:environment.identityQueue]) {
    return NO;
  }
  if (canonicalUserID) {
    [environment.controller switchToCanonicalUserID:canonicalUserID
                                             change:QONRemoteConfigControllerIdentityChangeBuild];
    [environment settleIdentity];
    // Binding forces one fetch, and an unscripted transport fails it. Step past
    // the resulting failure backoff so a test starts from a clean gate.
    environment.clock.now += 10000;
  }
  return YES;
}

/** Decoder that accepts every JSON value. */
static QONRemoteConfigValueDecoder QONRCPubAnyDecoder(void) {
  return ^id(NSData *rawData, __unused NSError **error) {
    return [NSJSONSerialization JSONObjectWithData:rawData
                                           options:NSJSONReadingFragmentsAllowed
                                             error:nil];
  };
}

/** Decoder that only accepts JSON strings with the given prefix. */
static QONRemoteConfigValueDecoder QONRCPubPrefixDecoder(NSString *prefix) {
  return ^id(NSData *rawData, NSError **error) {
    id value = [NSJSONSerialization JSONObjectWithData:rawData
                                               options:NSJSONReadingFragmentsAllowed
                                                 error:nil];
    if ([value isKindOfClass:NSString.class] && [(NSString *)value hasPrefix:prefix]) {
      return value;
    }
    if (error) {
      *error = [NSError errorWithDomain:@"io.qonversion.test" code:1 userInfo:nil];
    }
    return nil;
  };
}

NS_ASSUME_NONNULL_END
