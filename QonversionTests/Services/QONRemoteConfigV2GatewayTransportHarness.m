//
//  Headless mirror of QONRemoteConfigV2GatewayTransportTests.
//
//  XCTest needs a full Xcode install, so the transport slice is also runnable
//  from the command line, exactly like the fetch-policy harness:
//
//    clang -fobjc-arc -o /tmp/transport-harness \
//      QonversionTests/Services/QONRemoteConfigV2GatewayTransportHarness.m \
//      Sources/Qonversion/Qonversion/Services/QONRemoteConfigV2Transport/*.m \
//      Sources/Qonversion/Qonversion/Main/QONRemoteConfigV2Manager/QONRemoteConfigV2Models.m \
//      Sources/Qonversion/Qonversion/Main/QONRemoteConfigV2Manager/QONRemoteConfigV2FetchCoordinator.m \
//      $(find Sources -type d | sed 's/^/-I/') -framework Foundation
//

#import <Foundation/Foundation.h>

#import "QONRemoteConfigV2GatewayTransportFixtures.h"

// The harness links only the transport slice; the full SDK owns this helper.
id QONRemoteConfigPortableJSONObject(NSData *data, NSUInteger maximumBytes) {
  if (data.length == 0 || data.length > maximumBytes) return nil;
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSUInteger failures = 0;
static NSUInteger checks = 0;
#define QON_CHECK(condition, message) do { checks += 1; if (!(condition)) { \
  failures += 1; fprintf(stderr, "FAIL: %s\n", message); } } while (0)

#pragma mark - Environment

@interface QONRCV2HarnessEnvironment : NSObject
@property (nonatomic, strong) QONRCV2FakeHTTPExecutor *executor;
@property (nonatomic, strong) QONRCV2FakeLocalStorage *storage;
@property (nonatomic, strong) QONRemoteConfigV2GatewaySessionStore *sessionStore;
@property (nonatomic, strong) QONRemoteConfigV2ProjectIdentityStore *projectIdentityStore;
@property (nonatomic, strong) QONRCV2FakeClock *clock;
@property (nonatomic, strong) QONRCV2FakeInstallDateProvider *installDateProvider;
@property (nonatomic, strong) QONRemoteConfigV2GatewayTransport *transport;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *failureKinds;
@end

@implementation QONRCV2HarnessEnvironment

- (instancetype)init {
  self = [super init];
  if (self) {
    _executor = [QONRCV2FakeHTTPExecutor new];
    _storage = [QONRCV2FakeLocalStorage new];
    _sessionStore = [[QONRemoteConfigV2GatewaySessionStore alloc] initWithLocalStorage:_storage];
    _projectIdentityStore = [[QONRemoteConfigV2ProjectIdentityStore alloc]
        initWithLocalStorage:_storage
                     baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                projectToken:QONRCV2TestProjectToken];
    _clock = [QONRCV2FakeClock new];
    _clock.now = 1000000000000;
    _installDateProvider = [QONRCV2FakeInstallDateProvider new];
    _installDateProvider.seconds = @1600000000;
    _failureKinds = [NSMutableArray new];

    __weak typeof(self) weakSelf = self;
    _transport = [[QONRemoteConfigV2GatewayTransport alloc]
         initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
            projectToken:QONRCV2TestProjectToken
            httpExecutor:_executor
            sessionStore:_sessionStore
    projectIdentityStore:_projectIdentityStore
   clientContextProvider:QONRCV2ContextProvider(_installDateProvider)
                   clock:_clock
         failureObserver:^(QONRemoteConfigV2TransportFailureKind kind, NSNumber *statusCode) {
      [weakSelf.failureKinds addObject:@(kind)];
    }];
    [_transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  }
  return self;
}

- (QONRemoteConfigV2FetchResponse *)fetchWithIfNoneMatch:(NSString *)ifNoneMatch {
  __block QONRemoteConfigV2FetchResponse *result = nil;
  [self.transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:ifNoneMatch]
                    completion:^(QONRemoteConfigV2FetchResponse *response) {
    result = response;
  }];
  return result;
}

- (void)seedStoredSessionWithToken:(NSString *)token {
  QONRemoteConfigV2GatewaySession *session = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:token projectID:QONRCV2TestProjectID environment:@"production"
          expiresAtSeconds:0];
  QON_CHECK([self.sessionStore storeSession:session forScope:QONRCV2Scope(QONRCV2TestAnonUID)],
            "seeded session stored");
  // A stored session is only reusable while the ledger agrees with it, so a
  // seeded install must carry the id it would have learned.
  QON_CHECK([self.projectIdentityStore establishProjectID:QONRCV2TestProjectID
                                                 forScope:QONRCV2Scope(QONRCV2TestAnonUID)] !=
                QONRemoteConfigV2ProjectIdentityOutcomeConflict,
            "seeded project identity established");
}

- (void)enqueueBootstrapWithToken:(NSString *)token {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                        body:QONRCV2BootstrapBody(token, 0)
                                                     headers:nil]];
}

- (void)enqueueSnapshotSuccessWithBody:(NSData *)body {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                        body:body
                                                     headers:@{@"ETag": QONRCV2TestStrongETag}]];
}

@end

#pragma mark - Scenarios

static void TestRequestShapes(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [env fetchWithIfNoneMatch:nil];

  QON_CHECK(env.executor.requests.count == 2, "two requests issued");
  NSURLRequest *bootstrap = env.executor.requests[0];
  QON_CHECK([bootstrap.URL.absoluteString
                isEqualToString:@"https://gateway.test.example/v3/remote-config-v2/session"],
            "bootstrap url");
  QON_CHECK([bootstrap.HTTPMethod isEqualToString:@"POST"], "bootstrap method");
  QON_CHECK([QONRCV2Header(bootstrap, @"Authorization")
                isEqualToString:[@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]],
            "bootstrap authorization");
  QON_CHECK([QONRCV2Header(bootstrap, @"Content-Type") isEqualToString:@"application/json"],
            "bootstrap content type");
  QON_CHECK(QONRCV2Header(bootstrap, QONRemoteConfigV2GatewaySessionHeader) == nil,
            "bootstrap has no session header");
  QON_CHECK([QONRCV2JSONFromRequest(bootstrap) isEqual:@{@"user_uid": QONRCV2TestAnonUID}],
            "bootstrap body");

  NSURLRequest *snapshot = env.executor.requests[1];
  QON_CHECK([snapshot.URL.absoluteString
                isEqualToString:@"https://gateway.test.example/v3/remote-config-v2/snapshot"],
            "snapshot url");
  QON_CHECK([QONRCV2Header(snapshot, QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:@"session-token-1"], "snapshot session header");
  QON_CHECK(QONRCV2Header(snapshot, @"If-None-Match") == nil, "snapshot without validator");
  NSDictionary *body = QONRCV2JSONFromRequest(snapshot);
  QON_CHECK([body[@"client_context"] isEqual:(@{
    @"platform": @"ios", @"app_version": @"1.2.3", @"os_version": @"17.4",
    @"sdk_version": @"9.9.9", @"locale": @"en_US", @"device_model": @"iPhone15,2",
    @"device_installed_at": @1600000000,
  })], "snapshot client_context");
  QON_CHECK(body.count == 1, "snapshot body has only client_context");
}

static void TestIfNoneMatchForwarded(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env seedStoredSessionWithToken:@"session-token-1"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304 body:nil headers:nil]];
  [env fetchWithIfNoneMatch:QONRCV2TestStrongETag];

  QON_CHECK(env.executor.requests.count == 1, "no bootstrap with a stored session");
  QON_CHECK([QONRCV2Header(env.executor.requests[0], @"If-None-Match")
                isEqualToString:QONRCV2TestStrongETag], "validator forwarded verbatim");
}

static void TestExactBytes(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  NSData *body = QONRCV2NonCanonicalSnapshotBody();
  [env seedStoredSessionWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:body];

  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindSuccess, "success kind");
  QON_CHECK(QONRCV2DataIdenticalBytes(response.body, body), "exact snapshot bytes");
  QON_CHECK([response.strongETag isEqualToString:QONRCV2TestStrongETag], "exact strong etag");
}

static void TestMalformedSuccess(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env seedStoredSessionWithToken:@"session-token-1"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                       body:QONRCV2NonCanonicalSnapshotBody()
                                                    headers:@{@"ETag": @"W/\"weak\""}]];
  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure, "weak etag rejected");
  QON_CHECK([env.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindSnapshotMalformed)],
            "typed malformed failure");
}

static void TestNotModified(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env seedStoredSessionWithToken:@"session-token-1"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304 body:nil headers:nil]];
  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:QONRCV2TestStrongETag];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindNotModified, "304 kind");
  QON_CHECK(response.body == nil, "304 has no body");
  QON_CHECK([response.strongETag isEqualToString:QONRCV2TestStrongETag], "304 keeps validator");

  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304
                                                       body:nil
                                                    headers:@{@"ETag": QONRCV2TestStrongETag}]];
  QONRemoteConfigV2FetchResponse *headerValidated = [env fetchWithIfNoneMatch:
      @"\"0000000000000000000000000000000000000000000000000000000000000002\""];
  QON_CHECK(headerValidated.kind == QONRemoteConfigV2FetchResponseKindNotModified,
            "304 kind from header");
  QON_CHECK([headerValidated.strongETag isEqualToString:QONRCV2TestStrongETag],
            "304 validator from header");

  QONRCV2HarnessEnvironment *unconditional = [QONRCV2HarnessEnvironment new];
  [unconditional seedStoredSessionWithToken:@"session-token-1"];
  [unconditional.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304 body:nil headers:nil]];
  QONRemoteConfigV2FetchResponse *bogus = [unconditional fetchWithIfNoneMatch:nil];
  QON_CHECK(bogus.kind == QONRemoteConfigV2FetchResponseKindFailure,
            "304 without a validator is malformed");
  QON_CHECK([unconditional.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindSnapshotMalformed)],
            "typed malformed 304");
}

static void TestReBootstrapOnce(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  NSData *body = QONRCV2NonCanonicalSnapshotBody();
  [env seedStoredSessionWithToken:@"stale-token"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];
  [env enqueueBootstrapWithToken:@"fresh-token"];
  [env enqueueSnapshotSuccessWithBody:body];

  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindSuccess, "recovered success");
  QON_CHECK(QONRCV2DataIdenticalBytes(response.body, body), "recovered exact bytes");
  QON_CHECK(env.executor.requests.count == 3, "exactly three requests");
  QON_CHECK([env.executor.requests[1].URL.path isEqualToString:@"/v3/remote-config-v2/session"],
            "re-bootstrap issued");
  QON_CHECK([QONRCV2Header(env.executor.requests[2], QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:@"fresh-token"], "retry uses fresh token");
  QON_CHECK([[env.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)].sessionToken
                isEqualToString:@"fresh-token"], "fresh token persisted");
}

static void TestSecondUnauthorized(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env seedStoredSessionWithToken:@"stale-token"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];
  [env enqueueBootstrapWithToken:@"fresh-token"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure, "second 401 fails");
  QON_CHECK([response.statusCode isEqual:@401], "401 status surfaced");
  QON_CHECK(env.executor.requests.count == 3, "no loop after the second 401");
  QON_CHECK([env.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindSnapshotUnauthorized)],
            "typed unauthorized failure");
  QON_CHECK([env.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)] == nil,
            "rejected token dropped");
}

static void TestUnauthorizedOnFreshSession(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env enqueueBootstrapWithToken:@"fresh-token"];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure, "fresh 401 fails");
  QON_CHECK(env.executor.requests.count == 2, "no second bootstrap for a fresh session");
}

static void TestTypedFailures(void) {
  QONRCV2HarnessEnvironment *notFound = [QONRCV2HarnessEnvironment new];
  [notFound seedStoredSessionWithToken:@"session-token-1"];
  [notFound.executor enqueue:[QONRCV2ScriptedHTTPResponse status:404 body:nil headers:nil]];
  QONRemoteConfigV2FetchResponse *response = [notFound fetchWithIfNoneMatch:nil];
  QON_CHECK([response.statusCode isEqual:@404], "404 status surfaced");
  QON_CHECK([notFound.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindSnapshotNotFound)],
            "typed not found");

  QONRCV2HarnessEnvironment *unavailable = [QONRCV2HarnessEnvironment new];
  [unavailable seedStoredSessionWithToken:@"session-token-1"];
  [unavailable.executor enqueue:[QONRCV2ScriptedHTTPResponse status:503
                                                               body:nil
                                                            headers:@{@"Retry-After": @"12"}]];
  QONRemoteConfigV2FetchResponse *unavailableResponse = [unavailable fetchWithIfNoneMatch:nil];
  QON_CHECK([unavailableResponse.statusCode isEqual:@503], "503 status surfaced");
  QON_CHECK([unavailableResponse.retryAfterMilliseconds isEqual:@12000], "retry-after normalized");
  QON_CHECK([unavailable.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindSnapshotUnavailable)],
            "typed unavailable");

  NSArray *bootstrapCases = @[
    @[@401, @(QONRemoteConfigV2TransportFailureKindBootstrapUnauthorized)],
    @[@404, @(QONRemoteConfigV2TransportFailureKindBootstrapNotFound)],
    @[@503, @(QONRemoteConfigV2TransportFailureKindBootstrapUnavailable)],
  ];
  for (NSArray *testCase in bootstrapCases) {
    QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
    [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:[testCase[0] integerValue]
                                                         body:nil
                                                      headers:nil]];
    QONRemoteConfigV2FetchResponse *bootstrapResponse = [env fetchWithIfNoneMatch:nil];
    QON_CHECK(bootstrapResponse.kind == QONRemoteConfigV2FetchResponseKindFailure,
              "bootstrap failure");
    QON_CHECK([bootstrapResponse.statusCode isEqual:testCase[0]], "bootstrap status surfaced");
    QON_CHECK(env.executor.requests.count == 1, "snapshot skipped after bootstrap failure");
    QON_CHECK([env.failureKinds.lastObject isEqual:testCase[1]], "typed bootstrap failure");
  }

  QONRCV2HarnessEnvironment *malformed = [QONRCV2HarnessEnvironment new];
  [malformed.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:[@"{\"session_token\":\"\",\"project_id\":42,\"environment\":\"production\"}"
                 dataUsingEncoding:NSUTF8StringEncoding]
     headers:nil]];
  QONRemoteConfigV2FetchResponse *malformedResponse = [malformed fetchWithIfNoneMatch:nil];
  QON_CHECK(malformedResponse.kind == QONRemoteConfigV2FetchResponseKindFailure,
            "malformed bootstrap fails");
  QON_CHECK([malformed.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindBootstrapMalformed)],
            "typed malformed bootstrap");

  QONRCV2HarnessEnvironment *offline = [QONRCV2HarnessEnvironment new];
  [offline seedStoredSessionWithToken:@"session-token-1"];
  [offline.executor enqueue:[QONRCV2ScriptedHTTPResponse transportError]];
  QONRemoteConfigV2FetchResponse *offlineResponse = [offline fetchWithIfNoneMatch:nil];
  QON_CHECK(offlineResponse.statusCode == nil, "transport error has no status");
  QON_CHECK([offline.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindSnapshotTransport)],
            "typed transport failure");

  QONRCV2HarnessEnvironment *unbound = [QONRCV2HarnessEnvironment new];
  [unbound.transport updateScope:nil];
  QONRemoteConfigV2FetchResponse *unboundResponse = [unbound fetchWithIfNoneMatch:nil];
  QON_CHECK(unboundResponse.kind == QONRemoteConfigV2FetchResponseKindFailure, "unbound fails");
  QON_CHECK(unbound.executor.requests.count == 0, "unbound issues no request");
  QON_CHECK([unbound.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindNotConfigured)],
            "typed not configured");
}

static void TestSessionScoping(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env enqueueBootstrapWithToken:@"anon-token"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [env fetchWithIfNoneMatch:nil];

  QONRemoteConfigV2Scope *anonymous = QONRCV2Scope(QONRCV2TestAnonUID);
  QONRemoteConfigV2Scope *identified = QONRCV2Scope(@"identified-uid");
  QON_CHECK([[env.sessionStore sessionForScope:anonymous].sessionToken
                isEqualToString:@"anon-token"], "anonymous token persisted");
  QON_CHECK([env.sessionStore sessionForScope:identified] == nil,
            "identified scope has no token");

  [env.transport updateScope:identified];
  [env enqueueBootstrapWithToken:@"identified-token"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [env fetchWithIfNoneMatch:nil];

  QON_CHECK(env.executor.requests.count == 4, "identity change re-bootstraps");
  QON_CHECK([QONRCV2JSONFromRequest(env.executor.requests[2])
                isEqual:@{@"user_uid": @"identified-uid"}], "bootstrap uses the new uid");
  QON_CHECK([QONRCV2Header(env.executor.requests[3], QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:@"identified-token"], "old token never reused");
  QON_CHECK([env.sessionStore sessionForScope:anonymous] == nil,
            "retired identity token dropped");

  QONRCV2HarnessEnvironment *rebind = [QONRCV2HarnessEnvironment new];
  [rebind seedStoredSessionWithToken:@"anon-token"];
  [rebind.transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  QON_CHECK([[rebind.sessionStore sessionForScope:anonymous].sessionToken
                isEqualToString:@"anon-token"], "rebinding the same scope keeps the session");

  NSString *anonymousKey = [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:anonymous];
  NSString *identifiedKey = [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:identified];
  QON_CHECK(![anonymousKey isEqualToString:identifiedKey], "scoped storage keys differ");
  rebind.storage.objects[identifiedKey] = rebind.storage.objects[anonymousKey];
  QON_CHECK(rebind.storage.objects[identifiedKey] != nil, "replay fixture in place");
  QON_CHECK([rebind.sessionStore sessionForScope:identified] == nil,
            "a replayed record is rejected under another identity");
}

static void TestExpiredSession(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QONRemoteConfigV2GatewaySession *expired = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"expired-token" projectID:42 environment:@"production"
          expiresAtSeconds:env.clock.now / 1000 - 1];
  [env.sessionStore storeSession:expired forScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  [env enqueueBootstrapWithToken:@"fresh-token"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindSuccess, "expired session recovers");
  QON_CHECK(env.executor.requests.count == 2, "expired session bootstraps once");
  QON_CHECK([QONRCV2Header(env.executor.requests[1], QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:@"fresh-token"], "expired token not sent");
}

static void TestDeviceInstallDate(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QONRCV2FakeLocalStorage *deviceStorage = [QONRCV2FakeLocalStorage new];
  QONRemoteConfigV2DeviceInstallDateProvider *provider =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc] initWithLocalStorage:deviceStorage
                                                     systemInstallDateSeconds:@1500000000
                                                                        clock:env.clock];
  NSNumber *before = [provider deviceInstalledAtSeconds];
  QON_CHECK([before isEqual:@1500000000], "install date seeded from the device fact");

  for (NSString *key in deviceStorage.objects.allKeys) {
    if (![key isEqualToString:QONRemoteConfigV2DeviceInstallDateStorageKey]) {
      [deviceStorage removeObjectForKey:key];
    }
  }
  QONRemoteConfigV2DeviceInstallDateProvider *afterLogout =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc] initWithLocalStorage:deviceStorage
                                                     systemInstallDateSeconds:@1900000000
                                                                        clock:env.clock];
  QON_CHECK([[afterLogout deviceInstalledAtSeconds] isEqual:before],
            "install date survives a simulated logout");
  QON_CHECK(deviceStorage.objects.count == 1, "install date uses one unscoped record");
  QON_CHECK(![QONRemoteConfigV2DeviceInstallDateStorageKey containsString:QONRCV2TestAnonUID],
            "install date key carries no identity");

  QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
       initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
          projectToken:QONRCV2TestProjectToken
          httpExecutor:env.executor
          sessionStore:env.sessionStore
  projectIdentityStore:env.projectIdentityStore
 clientContextProvider:QONRCV2ContextProvider(provider)
                 clock:env.clock
       failureObserver:nil];
  [transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  [env enqueueBootstrapWithToken:@"anon-token"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
               completion:^(QONRemoteConfigV2FetchResponse *response) {}];

  [transport updateScope:QONRCV2Scope(@"anon-uid-after-logout")];
  [env enqueueBootstrapWithToken:@"post-logout-token"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
               completion:^(QONRemoteConfigV2FetchResponse *response) {}];

  NSDictionary *first = QONRCV2JSONFromRequest(env.executor.requests[1])[@"client_context"];
  NSDictionary *second = QONRCV2JSONFromRequest(env.executor.requests[3])[@"client_context"];
  QON_CHECK([first[@"device_installed_at"] isEqual:@1500000000], "install date sent");
  QON_CHECK([second[@"device_installed_at"] isEqual:first[@"device_installed_at"]],
            "install date unchanged after logout");

  QONRCV2HarnessEnvironment *unknown = [QONRCV2HarnessEnvironment new];
  unknown.installDateProvider.seconds = nil;
  [unknown enqueueBootstrapWithToken:@"session-token-1"];
  [unknown enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [unknown fetchWithIfNoneMatch:nil];
  NSDictionary *context = QONRCV2JSONFromRequest(unknown.executor.requests[1])[@"client_context"];
  QON_CHECK(context.count == 6 && context[@"device_installed_at"] == nil,
            "unknown install date is omitted");
}

static void TestContractHardening(void) {
  QONRCV2HarnessEnvironment *wrongEnvironment = [QONRCV2HarnessEnvironment new];
  [wrongEnvironment.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:[@"{\"session_token\":\"t\",\"project_id\":42,\"environment\":\"sandbox\"}"
                 dataUsingEncoding:NSUTF8StringEncoding]
     headers:nil]];
  QONRemoteConfigV2FetchResponse *response = [wrongEnvironment fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure,
            "cross-environment session rejected");
  QON_CHECK(wrongEnvironment.executor.requests.count == 1, "snapshot skipped for wrong env");
  QON_CHECK([wrongEnvironment.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)] == nil,
            "cross-environment session not stored");

  QONRCV2HarnessEnvironment *badToken = [QONRCV2HarnessEnvironment new];
  [badToken.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:[@"{\"session_token\":\"bad\\r\\ntoken\",\"project_id\":42,"
               "\"environment\":\"production\"}" dataUsingEncoding:NSUTF8StringEncoding]
     headers:nil]];
  QONRemoteConfigV2FetchResponse *badTokenResponse = [badToken fetchWithIfNoneMatch:nil];
  QON_CHECK(badTokenResponse.kind == QONRemoteConfigV2FetchResponseKindFailure,
            "unsendable token rejected");
  QON_CHECK([badToken.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindBootstrapMalformed)],
            "typed malformed token");

  QONRCV2HarnessEnvironment *zeroRetry = [QONRCV2HarnessEnvironment new];
  [zeroRetry seedStoredSessionWithToken:@"session-token-1"];
  [zeroRetry.executor enqueue:[QONRCV2ScriptedHTTPResponse status:503
                                                             body:nil
                                                          headers:@{@"Retry-After": @"0"}]];
  QONRemoteConfigV2FetchResponse *zeroRetryResponse = [zeroRetry fetchWithIfNoneMatch:nil];
  QON_CHECK(zeroRetryResponse.retryAfterMilliseconds == nil,
            "zero retry-after does not defeat backoff");

  NSArray<NSArray<NSString *> *> *urlCases = @[
    @[@"https://gateway.test.example", @"https://gateway.test.example/v3/remote-config-v2/session"],
    @[@"https://gateway.test.example/api",
      @"https://gateway.test.example/api/v3/remote-config-v2/session"],
    @[@"https://gateway.test.example/?trace=1",
      @"https://gateway.test.example/v3/remote-config-v2/session"],
    @[@"https://gateway.test.example/api#frag",
      @"https://gateway.test.example/api/v3/remote-config-v2/session"],
  ];
  for (NSArray<NSString *> *testCase in urlCases) {
    QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
    QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
         initWithBaseURL:[NSURL URLWithString:testCase[0]]
            projectToken:QONRCV2TestProjectToken
            httpExecutor:env.executor
            sessionStore:env.sessionStore
    projectIdentityStore:env.projectIdentityStore
   clientContextProvider:QONRCV2ContextProvider(env.installDateProvider)
                   clock:env.clock
         failureObserver:nil];
    [transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
    [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:503 body:nil headers:nil]];
    [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
                 completion:^(QONRemoteConfigV2FetchResponse *ignored) {}];
    QON_CHECK(env.executor.requests.count == 1, "route request issued");
    QON_CHECK([env.executor.requests[0].URL.absoluteString isEqualToString:testCase[1]],
              "route path survives the base url");
  }

  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QON_CHECK([[QONRemoteConfigV2GatewayTransport alloc]
       initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
          projectToken:@"bad\r\ntoken"
          httpExecutor:env.executor
          sessionStore:env.sessionStore
  projectIdentityStore:env.projectIdentityStore
 clientContextProvider:QONRCV2ContextProvider(env.installDateProvider)
                 clock:env.clock
       failureObserver:nil] == nil,
            "unsendable project token refused at construction");
}

static void TestSecretHygiene(void) {
  QONRemoteConfigV2GatewaySession *session = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"super-secret-token" projectID:42 environment:@"production"
          expiresAtSeconds:0];
  QON_CHECK(![session.description containsString:@"super-secret-token"],
            "description hides the token");
  QON_CHECK(![session.debugDescription containsString:@"super-secret-token"],
            "debugDescription hides the token");
}

#pragma mark - Learned project identity

// The numeric project_id is not a caller input. The gateway states it in the
// session bootstrap, the SDK learns it there, and everything downstream — the
// envelope expectation included — is built from what was learned.

static void TestBootstrapEstablishesTheProjectID(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  QON_CHECK([env.projectIdentityStore projectIDForScope:scope] == 0,
            "nothing may be known before the first bootstrap");

  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];

  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindSuccess, "the fetch must succeed");
  QON_CHECK(response.projectID == QONRCV2TestProjectID,
            "the success must carry the id the bootstrap stated");
  QON_CHECK([env.projectIdentityStore projectIDForScope:scope] == QONRCV2TestProjectID,
            "the first bootstrap must establish the id");

  // A second fetch reuses the stored session and must report the same id
  // without any further bootstrap.
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *again = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(again.kind == QONRemoteConfigV2FetchResponseKindSuccess &&
                again.projectID == QONRCV2TestProjectID,
            "a reused session must report the same learned id");
  QON_CHECK(env.executor.requests.count == 3, "the second fetch must not re-bootstrap");
}

static void TestAConflictingReBootstrapIsATypedFailure(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QON_CHECK([env fetchWithIfNoneMatch:nil].kind == QONRemoteConfigV2FetchResponseKindSuccess,
            "the establishing fetch must succeed");

  // The stored token is rejected, so the transport re-bootstraps — and this time
  // the gateway answers with a different project.
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:QONRCV2BootstrapBodyForProject(@"session-token-2", 0, QONRCV2TestProjectID + 1)
     headers:nil]];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure,
            "a conflicting project id must fail the fetch");
  QON_CHECK(response.projectID == 0, "a failure states no project id");
  QON_CHECK([env.failureKinds.lastObject
                isEqual:@(QONRemoteConfigV2TransportFailureKindProjectIdentityConflict)],
            "the failure must be typed as a project identity conflict");
  QON_CHECK([env.projectIdentityStore projectIDForScope:scope] == QONRCV2TestProjectID,
            "the conflicting id must never be re-learned");
  QON_CHECK([env.sessionStore sessionForScope:scope] == nil,
            "the conflicting session must not be stored");
  QON_CHECK(env.executor.requests.count == 4,
            "the snapshot must not be requested under the refused session");
}

static void TestTheLearnedProjectIDSurvivesStoreRecreation(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QON_CHECK([env fetchWithIfNoneMatch:nil].kind == QONRemoteConfigV2FetchResponseKindSuccess,
            "the establishing fetch must succeed");

  // Same storage, a brand new store object: the restart case.
  QONRemoteConfigV2ProjectIdentityStore *reopened =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:env.storage
                       baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                  projectToken:QONRCV2TestProjectToken];
  QON_CHECK([reopened projectIDForScope:scope] == QONRCV2TestProjectID,
            "a re-created store must still know the learned id");
  QON_CHECK([reopened establishProjectID:QONRCV2TestProjectID forScope:scope] ==
                QONRemoteConfigV2ProjectIdentityOutcomeConfirmed,
            "the same id must confirm, not re-establish");
  QON_CHECK([reopened establishProjectID:QONRCV2TestProjectID + 1 forScope:scope] ==
                QONRemoteConfigV2ProjectIdentityOutcomeConflict,
            "a different id must conflict across the restart too");
  QON_CHECK([reopened projectIDForScope:scope] == QONRCV2TestProjectID,
            "a refused conflict must leave the record untouched");
}

static void TestProjectIdentityIsKeyedWithoutTheIdentity(void) {
  QONRemoteConfigV2Scope *anonymous = QONRCV2Scope(QONRCV2TestAnonUID);
  QONRemoteConfigV2Scope *identified = QONRCV2Scope(@"identified-uid");
  QONRCV2FakeLocalStorage *storage = [QONRCV2FakeLocalStorage new];
  QONRemoteConfigV2ProjectIdentityStore *store =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:storage
                       baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                  projectToken:QONRCV2TestProjectToken];
  // Deliberate: a project id belongs to the project, not to the user, so a
  // logout and a fresh login must not launder a conflicting id past the check.
  QON_CHECK([[store storageKeyForScope:anonymous]
                isEqualToString:[store storageKeyForScope:identified]],
            "two identities of one project must share the project identity key");
  QON_CHECK(![[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:anonymous]
                isEqualToString:[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:identified]],
            "session tokens must still be keyed per identity");

  // A conflict is terminal, so the key must separate what legitimately carries
  // different numeric ids: another gateway, or another project token.
  QONRemoteConfigV2ProjectIdentityStore *otherGateway =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:storage
                       baseURL:[NSURL URLWithString:@"https://staging.gateway.test.example/"]
                  projectToken:QONRCV2TestProjectToken];
  QONRemoteConfigV2ProjectIdentityStore *otherToken =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:storage
                       baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                  projectToken:@"another-project-token"];
  QON_CHECK(![[store storageKeyForScope:anonymous]
                isEqualToString:[otherGateway storageKeyForScope:anonymous]],
            "another gateway must not share the project identity key");
  QON_CHECK(![[store storageKeyForScope:anonymous]
                isEqualToString:[otherToken storageKeyForScope:anonymous]],
            "another project token must not share the project identity key");
  QON_CHECK([store establishProjectID:QONRCV2TestProjectID forScope:anonymous] ==
                    QONRemoteConfigV2ProjectIdentityOutcomeEstablished &&
                [otherGateway establishProjectID:QONRCV2TestProjectID + 1 forScope:anonymous] ==
                    QONRemoteConfigV2ProjectIdentityOutcomeEstablished,
            "a staging deployment must establish its own id, not conflict");
  NSURL *noURL = nil;
  NSString *noToken = nil;
  QON_CHECK([[QONRemoteConfigV2ProjectIdentityStore alloc]
                 initWithLocalStorage:storage baseURL:noURL projectToken:noToken] == nil,
            "a store without a deployment to key by must refuse to exist");

  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QON_CHECK([env fetchWithIfNoneMatch:nil].kind == QONRemoteConfigV2FetchResponseKindSuccess,
            "the anonymous fetch must succeed");

  [env.transport updateScope:identified];
  [env.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:QONRCV2BootstrapBodyForProject(@"session-token-2", 0, QONRCV2TestProjectID + 1)
     headers:nil]];
  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure &&
                [env.failureKinds.lastObject
                    isEqual:@(QONRemoteConfigV2TransportFailureKindProjectIdentityConflict)],
            "a new identity must not be able to re-learn a different project id");
}

static void TestProjectIdentityPersistenceAndRange(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  env.storage.ignoreWrites = YES;
  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindFailure,
            "an id that cannot be made durable must fail the fetch");
  QON_CHECK([env.failureKinds.lastObject isEqual:
                @(QONRemoteConfigV2TransportFailureKindProjectIdentityPersistenceFailed)],
            "typed project identity persistence failure");
  QON_CHECK(env.executor.requests.count == 1,
            "the snapshot must not be requested without a durable project id");

  // Out of range at the source: the session refuses to exist at all, which the
  // bootstrap reports as malformed rather than carrying an uncheckable id.
  QONRCV2HarnessEnvironment *oversized = [QONRCV2HarnessEnvironment new];
  [oversized.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:QONRCV2BootstrapBodyForProject(@"session-token-1", 0, INT64_MAX)
     headers:nil]];
  QONRemoteConfigV2FetchResponse *rejected = [oversized fetchWithIfNoneMatch:nil];
  QON_CHECK(rejected.kind == QONRemoteConfigV2FetchResponseKindFailure &&
                [oversized.failureKinds.lastObject
                    isEqual:@(QONRemoteConfigV2TransportFailureKindBootstrapMalformed)],
            "a project id beyond the safe integer range must be refused");
  // Two distinct refusals share that one outcome, so pin each at its own layer:
  // the session never forms, and the store would refuse the id independently.
  QON_CHECK([[QONRemoteConfigV2GatewaySession alloc]
                 initWithSessionToken:@"session-token-1" projectID:INT64_MAX
                          environment:@"production" expiresAtSeconds:0] == nil,
            "a session must not form around an uncheckable project id");
  QON_CHECK([oversized.projectIdentityStore projectIDForScope:QONRCV2Scope(QONRCV2TestAnonUID)] == 0,
            "a refused bootstrap must learn nothing");
  QON_CHECK([oversized.projectIdentityStore establishProjectID:INT64_MAX
                                                      forScope:QONRCV2Scope(QONRCV2TestAnonUID)] ==
                QONRemoteConfigV2ProjectIdentityOutcomeUnusable,
            "the store must refuse an out-of-range id on its own");
  QON_CHECK([oversized.projectIdentityStore establishProjectID:0
                                                      forScope:QONRCV2Scope(QONRCV2TestAnonUID)] ==
                QONRemoteConfigV2ProjectIdentityOutcomeUnusable,
            "zero is not a project id the store will keep");
}

// A stored session is a token, not an authority on which project answers. Only a
// live bootstrap establishes the id, so a session the ledger cannot vouch for is
// dropped rather than fetched with.
static void TestAStoredSessionTheLedgerCannotVouchForIsDropped(void) {
  QONRCV2HarnessEnvironment *env = [QONRCV2HarnessEnvironment new];
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  QONRemoteConfigV2GatewaySession *session = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"orphan-token" projectID:QONRCV2TestProjectID
               environment:@"production" expiresAtSeconds:0];
  QON_CHECK([env.sessionStore storeSession:session forScope:scope],
            "the orphan session must be stored");
  QON_CHECK([env.projectIdentityStore projectIDForScope:scope] == 0,
            "the ledger must know nothing about it");

  [env enqueueBootstrapWithToken:@"session-token-1"];
  [env enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *response = [env fetchWithIfNoneMatch:nil];

  QON_CHECK(response.kind == QONRemoteConfigV2FetchResponseKindSuccess,
            "the fetch must recover by bootstrapping");
  QON_CHECK(env.executor.requests.count == 2,
            "an unvouched session must not be reused");
  QON_CHECK([QONRCV2Header(env.executor.requests[1], QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:@"session-token-1"],
            "the snapshot must use the freshly bootstrapped token");
  QON_CHECK([env.projectIdentityStore projectIDForScope:scope] == QONRCV2TestProjectID,
            "the id must be established by the bootstrap, never by the stored session");

  // Same rule when the session disagrees rather than being unknown: it is
  // dropped, and the bootstrap that replaces it decides.
  QONRCV2HarnessEnvironment *rewritten = [QONRCV2HarnessEnvironment new];
  [rewritten seedStoredSessionWithToken:@"legitimate-token"];
  QONRemoteConfigV2GatewaySession *foreign = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"rewritten-token" projectID:QONRCV2TestProjectID + 1
               environment:@"production" expiresAtSeconds:0];
  QON_CHECK([rewritten.sessionStore storeSession:foreign forScope:scope],
            "the rewritten session must be stored");
  [rewritten enqueueBootstrapWithToken:@"session-token-1"];
  [rewritten enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *recovered = [rewritten fetchWithIfNoneMatch:nil];
  QON_CHECK(recovered.kind == QONRemoteConfigV2FetchResponseKindSuccess &&
                recovered.projectID == QONRCV2TestProjectID,
            "a rewritten session must not carry its own project id into admission");
  QON_CHECK(rewritten.executor.requests.count == 2,
            "the rewritten session must be replaced, not reused");
}

#pragma mark - Activation ack

/** Walks the bounded retry ladder to its end without racing the timer it arms. */
static void RunAckRetryLadder(QONRCV2AckEnvironment *env) {
  [env settle];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2ActivationAckMaximumAttempts; attempt++) {
    QON_CHECK(env.scheduler.pendingCount > 0, "a retry must be scheduled after every failed attempt");
    [env.scheduler runAll];
    [env settle];
  }
}

static void TestAnAckMatchesTheGatewayContractExactly(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 1, "exactly one ack must be sent");
  NSURLRequest *ack = env.gateway.ackRequests.firstObject;
  QON_CHECK([ack.HTTPMethod isEqualToString:@"POST"], "ack method");
  QON_CHECK([ack.URL.absoluteString
                isEqualToString:@"https://gateway.test.example/v3/remote-config-v2/ack"],
            "ack url");
  QON_CHECK([QONRCV2Header(ack, @"Authorization")
                isEqualToString:[@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]],
            "ack authorization");
  QON_CHECK([QONRCV2Header(ack, @"Content-Type") isEqualToString:@"application/json"],
            "ack content type");
  QON_CHECK([QONRCV2Header(ack, QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:QONRCV2SeededSessionToken],
            "the ack must ride the very session the snapshot was read under");
  QON_CHECK([QONRCV2JSONFromRequest(ack) isEqual:(@{
    @"release_number": @(QONRCV2AckRelease7),
    @"activated_at": @(QONRCV2AckActivatedAtSeconds),
  })], "ack body");
  QON_CHECK(QONRCV2Header(ack, @"If-None-Match") == nil, "an ack carries no validator");

  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease7,
            "a delivered release must be settled durably");
  QON_CHECK(sender.droppedAckCount == 0, "nothing was dropped");
}

static void TestADeliveredReleaseIsNeverAckedTwice(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  // The same release re-reported: an implicit activation followed by an
  // explicit activate().
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  // ...and re-reported after a rebind, which is what a second cold start does.
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 1, "a settled release must never be acked twice");
}

static void TestA401ReBootstrapsOnceAndRetriesTheAck(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:401];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 2, "the 401 must license exactly one more attempt");
  QON_CHECK(env.gateway.sessionRequests.count == 1, "exactly one re-bootstrap, and no other");
  QON_CHECK([QONRCV2Header(env.gateway.ackRequests[0], QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:QONRCV2SeededSessionToken] &&
                [QONRCV2Header(env.gateway.ackRequests[1], QONRemoteConfigV2GatewaySessionHeader)
                    isEqualToString:QONRCV2MintedSessionToken],
            "the second attempt must use the freshly minted session");
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease7,
            "the retried ack must be delivered and settled");
  QON_CHECK(sender.droppedAckCount == 0, "nothing was dropped");
  // The re-bootstrap is the transport's business, not the sender's retry budget.
  QON_CHECK(env.scheduler.requestedDelays.count == 0, "a 401 must not spend a retry");
}

static void TestA401ThatSurvivesTheReBootstrapIsPermanent(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:401 times:2];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 2, "a second 401 must end the ack");
  QON_CHECK(sender.droppedAckCount == 1, "the ack is dropped");
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease7,
            "permanent is an answer: the release is settled, not left owed");
  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count == 2, "and nothing retries it");
}

static void TestAPermanentRefusalSettlesTheRelease(void) {
  // A gateway that does not serve /ack at all answers every ack with 404.
  // Forgetting such a release would re-queue and re-POST the same ack on every
  // start and every binding.
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:404 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 1, "a 404 is answered once");
  QON_CHECK(sender.droppedAckCount == 1, "the ack is dropped");
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease7,
            "a permanently refused release must be settled, not forgotten");

  [env.scheduler runAll];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  // A whole new process over the same durable state must stay silent as well.
  [[env makeSender] bindScope:QONRCV2AckScopeA()];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 1,
            "a gateway without the route must never become a restart storm");
}

static void TestA503IsRetriedToTheBoundAndThenDropped(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  RunAckRetryLadder(env);

  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "the ladder is bounded");
  // Half the cap plus jitter, never full-downward jitter.
  QON_CHECK([env.scheduler.requestedDelays isEqual:(@[@750, @1500])], "retry delays");
  QON_CHECK(env.scheduler.pendingCount == 0, "nothing is scheduled after the bound");
  QON_CHECK(sender.droppedAckCount == 1, "the ack is dropped");
  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "and stays dropped");
  // Dropped in this process, still owed: the record is what a later start picks up.
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending.releaseNumber == QONRCV2AckRelease7,
            "an abandoned ack stays owed durably");
}

static void TestAnExhaustedLadderIsNotReArmedByARebinding(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  RunAckRetryLadder(env);

  // An identify that lands on the same identity, a re-report of the same
  // activation, and a round trip through another identity.
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [sender bindScope:QONRCV2AckScopeB()];
  [sender bindScope:QONRCV2AckScopeA()];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "a rebind must not buy the same release another ladder");

  // Only a NEWER release re-arms delivery.
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts + 1,
            "a newer release re-arms delivery");
  QON_CHECK(QONRCV2AckReleaseNumber(env.gateway.ackRequests.lastObject) == QONRCV2AckRelease9,
            "and it is the newer release that is reported");
}

static void TestAnUnbindAndRebindDoesNotBuyTheSameReleaseANewLadder(void) {
  // The shape every identity change has: the scope is unbound first and bound
  // again afterwards. Neither half may restart a ladder this process spent.
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  RunAckRetryLadder(env);

  for (NSUInteger round = 0; round < 3; round++) {
    [sender bindScope:nil];
    [sender bindScope:QONRCV2AckScopeA()];
    [env settle];
  }

  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "identity churn must never re-arm an abandoned ack");
  QON_CHECK(sender.droppedAckCount == 1, "and must never re-count the drop");
}

static void TestAPartlySpentLadderIsNotRestartedByARebinding(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count == 1, "one attempt is spent");

  // Rebinding in the middle of a ladder resumes it rather than starting over,
  // so the total stays bounded however often the identity is rebound.
  for (NSUInteger round = 0; round < 5; round++) {
    [sender bindScope:nil];
    [sender bindScope:QONRCV2AckScopeA()];
    [env settle];
  }

  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts,
            "the bound is per process, not per binding");
  QON_CHECK(sender.droppedAckCount == 1, "and the ack ends abandoned exactly once");
}

static void TestAnOlderActivationNeverSupersedesANewerOne(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [env settle];

  // Two reads that raced past each other can report the older release last.
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];
  [env.scheduler runAll];
  [env settle];

  for (NSURLRequest *request in env.gateway.ackRequests) {
    QON_CHECK(QONRCV2AckReleaseNumber(request) == QONRCV2AckRelease9,
              "an older activation must never displace the release that serves");
  }
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease9,
            "and the newer release is the one that settles");
}

static void TestAnOlderReleaseCannotReAckASettledScope(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [env settle];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 1,
            "settled is a high-water mark: an older release is already answered for");
}

static void TestANewerActivationSupersedesTheQueuedOne(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  env.clock.now = QONRCV2AckLaterActivatedAtSeconds * 1000;
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 2, "the newer activation is sent at once");
  QON_CHECK([QONRCV2JSONFromRequest(env.gateway.ackRequests[1]) isEqual:(@{
    @"release_number": @(QONRCV2AckRelease9),
    @"activated_at": @(QONRCV2AckLaterActivatedAtSeconds),
  })], "the superseding ack states its own activation time");
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease9,
            "the newer release settles the scope");
  // The superseded retry never fires, so release 7 is never re-sent.
  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count == 2 &&
                QONRCV2AckReleaseNumber(env.gateway.ackRequests[0]) == QONRCV2AckRelease7 &&
                QONRCV2AckReleaseNumber(env.gateway.ackRequests[1]) == QONRCV2AckRelease9,
            "a superseded ack is never re-sent");
}

static void TestAPendingAckSurvivesAProcessRestart(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503 times:QONRemoteConfigV2ActivationAckMaximumAttempts];
  QONRemoteConfigV2ActivationAckSender *crashed = [env makeSender];
  [crashed bindScope:QONRCV2AckScopeA()];
  [crashed recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  RunAckRetryLadder(env);
  QON_CHECK(crashed.droppedAckCount == 1, "the first process abandons the ack");

  // A new process: new sender, new queue, new scheduler, a freshly built store
  // over the same durable bytes.
  env.scheduler = [QONRCV2ManualScheduler new];
  env.clock.now = QONRCV2AckLaterActivatedAtSeconds * 1000;
  QONRemoteConfigV2ActivationAckSender *restarted = [env makeSender];
  [restarted bindScope:QONRCV2AckScopeA()];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count ==
                (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts + 1,
            "the next process delivers what this one could not");
  // The ack still reports when the release was ACTIVATED, not when it was
  // finally delivered.
  QON_CHECK([QONRCV2JSONFromRequest(env.gateway.ackRequests.lastObject) isEqual:(@{
    @"release_number": @(QONRCV2AckRelease7),
    @"activated_at": @(QONRCV2AckActivatedAtSeconds),
  })], "a late-delivered ack still reports when serving started");
  QONRemoteConfigV2ActivationAckRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.pending == nil && record.settledReleaseNumber == QONRCV2AckRelease7,
            "and settles it");
  QON_CHECK(restarted.droppedAckCount == 0, "the new process drops nothing");
}

static void TestRebindingTheSameIdentityDoesNotReSendAnAckUnderWay(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  // An identify that resolves to the identity already bound.
  [sender bindScope:QONRCV2AckScopeA()];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 1, "a no-op identify costs no request");
  QON_CHECK(env.scheduler.pendingCount == 1, "and the armed retry is still the one that will run");
  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.gateway.ackRequests.count == 2, "the retry runs exactly once");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()].settledReleaseNumber == QONRCV2AckRelease7,
            "and settles the release");
}

static void TestAnAckIsNeverSentUnderAnotherIdentitysSession(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [env settle];
  // The transport now addresses another identity than the one the ack was
  // queued for.
  [env useIdentityScope:QONRCV2AckScopeB()];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 0, "no request may be made under the wrong identity");
  QON_CHECK(sender.droppedAckCount == 0, "a refusal costs no retry budget");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()].pending.releaseNumber == QONRCV2AckRelease7,
            "the ack stays queued for the identity that owes it");
}

static void TestAnActivationOfAnUnboundScopeIsIgnored(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [sender bindScope:QONRCV2AckScopeB()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 0, "an unbound activation is not an ack");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()] == nil, "and is never made durable");
}

static void TestBindingAnotherIdentityFencesAnAckOnTheWire(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [env settle];

  [env useIdentityScope:QONRCV2AckScopeB()];
  [sender bindScope:QONRCV2AckScopeB()];
  [env settle];
  [env.scheduler runAll];
  [env settle];

  // The retry the 503 scheduled belongs to the previous identity.
  QON_CHECK(env.gateway.ackRequests.count == 1, "a fenced retry must never fire");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()].pending.releaseNumber == QONRCV2AckRelease7,
            "and the previous identity keeps owing it");
}

static void TestAReleaseNumberThatCouldNeverAddressAnythingIsRefused(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2ActivationAckSender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:0];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:-1];
  [env settle];

  QON_CHECK(env.gateway.ackRequests.count == 0, "an unaddressable release is never acked");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()] == nil, "and never persisted");
}

#pragma mark - Client telemetry

/** Walks a telemetry retry ladder to its bound, one manual tick per attempt. */
static void RunTelemetryRetryLadder(QONRCV2AckEnvironment *env) {
  [env settle];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2TelemetryMaximumAttempts; attempt++) {
    QON_CHECK(env.scheduler.pendingCount > 0,
              "a telemetry retry must be scheduled after every failed attempt");
    [env.scheduler runAll];
    [env settle];
  }
}

static void TestATelemetryBatchMatchesTheGatewayContractExactly(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 1, "exactly one telemetry request must be sent");
  NSURLRequest *request = env.gateway.telemetryRequests.firstObject;
  QON_CHECK([request.HTTPMethod isEqualToString:@"POST"], "telemetry method");
  QON_CHECK([request.URL.absoluteString
                isEqualToString:@"https://gateway.test.example/v3/remote-config-v2/telemetry"],
            "telemetry url");
  QON_CHECK([QONRCV2Header(request, @"Authorization")
                isEqualToString:[@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]],
            "telemetry authorization");
  QON_CHECK([QONRCV2Header(request, @"Content-Type") isEqualToString:@"application/json"],
            "telemetry content type");
  QON_CHECK([QONRCV2Header(request, QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:QONRCV2SeededSessionToken],
            "telemetry must ride the very session the snapshot was read under");
  QON_CHECK(QONRCV2Header(request, @"If-None-Match") == nil, "telemetry carries no validator");
  QON_CHECK([QONRCV2JSONFromRequest(request) isEqual:(@{
    @"events": @[@{
      @"kind": @"decode_failure",
      @"logical_key": QONRCV2TelemetryKeyAlpha,
      @"release_number": @(QONRCV2TelemetryRelease4),
      @"count": @3,
      @"last_occurred_at": @(QONRCV2TelemetryObservedAtSeconds),
    }],
  })], "telemetry body");
  QON_CHECK([env telemetryRecordForScope:QONRCV2AckScopeA()] == nil,
            "a delivered batch must leave nothing behind on disk");
  QON_CHECK(sender.droppedEventCount == 0, "nothing was dropped");
}

static void TestOnlyDecodeFailuresCarryALogicalKey(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:nil
       releaseNumber:0];
  [sender noteSuccessfulFetch];
  [env settle];

  NSDictionary *event = QONRCV2TelemetryOnlyEvent(env.gateway.telemetryRequests.firstObject);
  QON_CHECK([event[@"kind"] isEqualToString:@"read_before_activate"], "keyless kind name");
  QON_CHECK(event[@"logical_key"] == nil, "a keyless kind must not state a logical key");
  QON_CHECK([event[@"release_number"] isEqual:@0], "an unknown release is stated as 0");
}

static void TestAKeyRuleViolationIsDroppedRatherThanSent(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  // A decode failure without a key, and a keyless kind with one: the gateway
  // would reject the whole batch either landed in.
  [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure logicalKey:nil releaseNumber:1];
  [sender recordKind:QONRemoteConfigV2TelemetryKindImplicitActivation
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:1];
  [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:@"control\tcharacter"
       releaseNumber:1];
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 0, "a violation must never reach the gateway");
  QON_CHECK(sender.droppedEventCount == 3, "and must be counted as dropped");
}

static void TestRepeatedFailuresCoalesceIntoOneEvent(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 500);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 1,
            "five hundred identical failures must cost one request");
  NSDictionary *event = QONRCV2TelemetryOnlyEvent(env.gateway.telemetryRequests.firstObject);
  QON_CHECK([event[@"count"] isEqual:@500], "and must be reported as one counted event");
}

static void TestA400DropsTheBatchPermanently(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptTelemetryStatus:400 times:8];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 2);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 1, "a 400 must never be retried");
  QON_CHECK(env.scheduler.pendingCount == 0, "and must not even schedule one");
  QON_CHECK(sender.droppedEventCount == 2, "the refused events are dropped");
  QON_CHECK([env telemetryRecordForScope:QONRCV2AckScopeA()] == nil,
            "and are gone from disk, so no restart can re-offer them");
}

static void TestATelemetry503IsRetriedToTheBoundAndThenDropped(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptTelemetryStatus:503 times:8];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  RunTelemetryRetryLadder(env);

  QON_CHECK(env.gateway.telemetryRequestCount ==
                (NSUInteger)QONRemoteConfigV2TelemetryMaximumAttempts,
            "the ladder must stop at the bound");
  QON_CHECK(sender.droppedEventCount == 1, "the abandoned batch is counted");
  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.gateway.telemetryRequestCount ==
                (NSUInteger)QONRemoteConfigV2TelemetryMaximumAttempts,
            "and nothing re-arms it");
}

static void TestA401ReBootstrapsOnceAndKeepsTheSharedSession(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptTelemetryStatus:401];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.sessionRequests.count == 1, "a 401 must re-bootstrap exactly once");
  QON_CHECK(env.gateway.telemetryRequestCount == 2, "and retry the batch once");
  QON_CHECK([QONRCV2Header(env.gateway.telemetryRequests.lastObject,
                           QONRemoteConfigV2GatewaySessionHeader)
                isEqualToString:QONRCV2MintedSessionToken],
            "the retry rides the freshly minted session");
  QON_CHECK([env.sessionStore sessionForScope:QONRCV2AckScopeA()] != nil,
            "a 401 on the telemetry route must never leave the read path without a session");
  QON_CHECK(sender.droppedEventCount == 0, "nothing was dropped");
}

static void TestTelemetryIsNeverSentUnderAnotherIdentitysSession(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  // The transport moved to another identity before the flush could go out.
  [env useIdentityScope:QONRCV2AckScopeB()];
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 0,
            "one identity's session may never carry another's telemetry");
  QONRemoteConfigV2TelemetryRecord *record = [env telemetryRecordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == 1, "and the events stay owed by the identity that made them");
}

static void TestABufferedBatchSurvivesAProcessRestart(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  env.gateway.hangTelemetry = YES;
  QONRemoteConfigV2TelemetrySender *first = [env makeTelemetrySender];
  [first bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(first, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 4);
  [first noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 1, "the first process got as far as the wire");
  QONRemoteConfigV2TelemetryRecord *record = [env telemetryRecordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == 1 && record.events.firstObject.count == 4,
            "an in-flight batch stays durable until it settles");

  // A new process over the same disk: the batch is still owed.
  env.gateway.hangTelemetry = NO;
  QONRemoteConfigV2TelemetrySender *second = [env makeTelemetrySender];
  [second bindScope:QONRCV2AckScopeA()];
  [second noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 2, "the next process delivers it");
  NSDictionary *event = QONRCV2TelemetryOnlyEvent(env.gateway.telemetryRequests.lastObject);
  QON_CHECK([event[@"count"] isEqual:@4], "with the count the dead process had accumulated");
  QON_CHECK([env telemetryRecordForScope:QONRCV2AckScopeA()] == nil, "and clears the buffer");
}

/**
 The worst case the durable record has to hold: a full batch on the wire AND a
 map that filled up again behind it.

 This is the shape that made the write fail silently before the record cap was
 sized for both — the moment with the most to lose is exactly the moment the
 buffer stopped being writable.
 */
static void TestAFullBatchAndARefilledMapBothSurviveARestart(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  env.gateway.hangTelemetry = YES;
  // The threshold is raised out of the way so the test, not the buffer, decides
  // when the batch leaves.
  QONRemoteConfigV2TelemetrySender *first = [env makeTelemetrySenderWithFlushThreshold:1000];
  [first bindScope:QONRCV2AckScopeA()];
  NSUInteger total = QONRemoteConfigV2TelemetryMaximumBatchEntries +
      QONRemoteConfigV2TelemetryMaximumEntries;
  // A full batch's worth of distinct keys, shipped and then left hanging.
  for (NSUInteger index = 0; index < QONRemoteConfigV2TelemetryMaximumBatchEntries; index++) {
    [first recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
           logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
        releaseNumber:QONRCV2TelemetryRelease4];
  }
  [first noteSuccessfulFetch];
  [env settle];
  // ...and a full map's worth accumulating behind it while it hangs.
  for (NSUInteger index = QONRemoteConfigV2TelemetryMaximumBatchEntries; index < total; index++) {
    [first recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
           logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
        releaseNumber:QONRCV2TelemetryRelease4];
  }
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount == 1, "one batch is stuck on the wire");
  QON_CHECK(QONRCV2TelemetryEvents(env.gateway.telemetryRequests.firstObject).count ==
                QONRemoteConfigV2TelemetryMaximumBatchEntries,
            "and it is a full one");
  QONRemoteConfigV2TelemetryRecord *record = [env telemetryRecordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == total,
            "the durable buffer holds the batch in flight AND the map behind it");
  QON_CHECK(first.droppedEventCount == 0, "nothing was dropped to make it fit");

  // A new process over the same disk delivers every one of them.
  env.gateway.hangTelemetry = NO;
  QONRemoteConfigV2TelemetrySender *second = [env makeTelemetrySender];
  [second bindScope:QONRCV2AckScopeA()];
  for (NSUInteger pass = 0; pass < 8; pass++) {
    [second noteSuccessfulFetch];
    [env settle];
  }
  NSMutableSet<NSString *> *keys = [NSMutableSet new];
  for (NSURLRequest *request in env.gateway.telemetryRequests) {
    for (NSDictionary *event in QONRCV2TelemetryEvents(request)) {
      [keys addObject:event[@"logical_key"]];
    }
  }
  QON_CHECK(keys.count == total, "every key the dead process buffered reaches the gateway");
  QON_CHECK([env telemetryRecordForScope:QONRCV2AckScopeA()] == nil, "and the buffer is cleared");
}

static void TestABatchNeverStatesMoreEventsThanTheContractAllows(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  // A full buffer against the shipped threshold: more distinct entries than one
  // request may carry, so the flush has to split them.
  for (NSUInteger index = 0; index < QONRemoteConfigV2TelemetryMaximumEntries; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [env settle];

  QON_CHECK(env.gateway.telemetryRequestCount >= 1, "a full buffer flushes on its own");
  NSUInteger total = 0;
  NSMutableSet<NSString *> *keys = [NSMutableSet new];
  for (NSUInteger pass = 0; pass < 8; pass++) {
    // Whatever a batch left behind goes out at the next opportunity.
    [sender noteSuccessfulFetch];
    [env settle];
  }
  for (NSURLRequest *request in env.gateway.telemetryRequests) {
    NSArray *events = QONRCV2TelemetryEvents(request);
    QON_CHECK(events.count <= QONRemoteConfigV2TelemetryMaximumBatchEntries,
              "no request may state more events than the contract allows");
    total += events.count;
    for (NSDictionary *event in events) [keys addObject:event[@"logical_key"]];
  }
  QON_CHECK(total == QONRemoteConfigV2TelemetryMaximumEntries,
            "and every distinct entry is reported exactly once");
  QON_CHECK(keys.count == QONRemoteConfigV2TelemetryMaximumEntries, "with no key lost or repeated");
}

static void TestAFullBufferSplitsAtTheBatchCap(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  // The threshold is raised to the bound so the whole buffer flushes at once:
  // the split is then the batch cap doing its job, not the threshold.
  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:64];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 64; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [env settle];

  QON_CHECK(env.transport.batchCount == 1, "one batch went out");
  QON_CHECK(env.transport.lastBatch.events.count == QONRemoteConfigV2TelemetryMaximumBatchEntries,
            "capped at exactly what one request may carry");

  [sender noteSuccessfulFetch];
  [env settle];
  QON_CHECK(env.transport.batchCount == 2, "and the remainder follows");
  QON_CHECK(env.transport.lastBatch.events.count == 64 -
                QONRemoteConfigV2TelemetryMaximumBatchEntries,
            "carrying exactly what was left");
  QON_CHECK(env.transport.allEvents.count == 64, "nothing was lost in the split");
}

#pragma mark - Client telemetry, sender rules

static void TestAFlushIsDueAtTheThresholdAndNotBefore(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:10];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 9; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [env settle];
  QON_CHECK(env.transport.batchCount == 0, "nine distinct entries are not yet a flush");

  [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:@"key-9"
       releaseNumber:QONRCV2TelemetryRelease4];
  [env settle];
  QON_CHECK(env.transport.batchCount == 1, "the tenth is");
  QON_CHECK(env.transport.lastBatch.events.count == 10, "and it carries all ten");
}

static void TestTheTickFlushesABufferBelowTheThreshold(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [env settle];
  QON_CHECK(env.transport.batchCount == 0, "one entry is far below the threshold");
  QON_CHECK(env.scheduler.pendingCount > 0, "so the periodic tick must be armed");

  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.transport.batchCount == 1, "and the tick is what ships it");
}

static void TestTheCoalescingMapIsBounded(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  // Threshold above the bound, so nothing flushes and the map itself is the
  // thing under test.
  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 200; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [env settle];

  QON_CHECK(sender.droppedEventCount == 200 - 64,
            "everything past the bound is dropped rather than buffered");
  QONRemoteConfigV2TelemetryRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == 64, "and the durable buffer never exceeds the bound");
}

static void TestAnEntryIsKeyedByKindAndKeyOnly(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 4, 2);
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyBeta, 4, 1);
  [sender recordKind:QONRemoteConfigV2TelemetryKindPreloadCorrupt logicalKey:nil releaseNumber:0];
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.transport.batchCount == 1, "one flush");
  NSArray<QONRemoteConfigV2TelemetryEvent *> *events = env.transport.lastBatch.events;
  QON_CHECK(events.count == 3, "a different kind or key is a different entry");
  QON_CHECK(events.firstObject.count == 2, "and the identical one coalesced");
}

/**
 A release rolling over between two flushes must not split one key in two.

 The gateway refuses a whole batch that names the same (kind, logical_key)
 twice, so the release number is an attribute of the entry rather than part of
 its identity: the counts add and the newer release wins.
 */
static void TestAReleaseRolloverKeepsOneEntry(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 4, 2);
  // The app fetched and activated release 5, and the same key still fails.
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 5, 3);
  // And a read that started before the activation lands afterwards: an older
  // release reported late must not drag the entry backwards.
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 4, 1);
  [sender noteSuccessfulFetch];
  [env settle];

  NSArray<QONRemoteConfigV2TelemetryEvent *> *events = env.transport.lastBatch.events;
  QON_CHECK(events.count == 1, "one key across two releases stays one entry");
  QON_CHECK(events.firstObject.count == 6, "with every release's occurrences added up");
  QON_CHECK(events.firstObject.releaseNumber == 5,
            "and the newest release number, whatever order they arrived in");
}

static void TestACountSaturatesAtTheContractCap(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetryStore *store =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:env.storage];
  QONRemoteConfigV2TelemetryEvent *saturated = [[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:QONRCV2TelemetryRelease4
               count:QONRemoteConfigV2TelemetryMaximumEventCount
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds];
  NSArray<QONRemoteConfigV2TelemetryEvent *> *only = @[saturated];
  QONRemoteConfigV2TelemetryRecord *record =
      [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:only];
  QON_CHECK([store storeRecord:record forScope:QONRCV2AckScopeA()], "a capped buffer is writable");

  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [env settle];

  QONRemoteConfigV2TelemetryEvent *shipped = env.transport.lastBatch.events.firstObject;
  QON_CHECK(shipped.count == QONRemoteConfigV2TelemetryMaximumEventCount,
            "the count saturates rather than exceeding what the contract allows");
  QON_CHECK(sender.droppedEventCount == 3, "and the occurrences past the cap are counted as lost");
}

static void TestAStaleEventIsPrunedInsteadOfPoisoningItsBatch(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetryStore *store =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:env.storage];
  // A phone that was offline for a month, and a clock that ran ahead.
  QONRemoteConfigV2TelemetryEvent *ancient = [[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:QONRCV2TelemetryRelease4
               count:9
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds - 31 * 24 * 60 * 60];
  QONRemoteConfigV2TelemetryEvent *fromTheFuture = [[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindPreloadCorrupt
          logicalKey:nil
       releaseNumber:0
               count:2
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds + 3600];
  NSArray<QONRemoteConfigV2TelemetryEvent *> *stale = @[ancient, fromTheFuture];
  QONRemoteConfigV2TelemetryRecord *record =
      [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:stale];
  QON_CHECK([store storeRecord:record forScope:QONRCV2AckScopeA()], "the stale buffer is writable");

  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:64
                                                               flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  // A fresh observation of a third key, shipped in the very same batch.
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyBeta, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.transport.batchCount == 1, "the batch still goes out");
  NSArray<QONRemoteConfigV2TelemetryEvent *> *events = env.transport.lastBatch.events;
  QON_CHECK(events.count == 1, "carrying only what the server would accept");
  QON_CHECK([events.firstObject.logicalKey isEqualToString:QONRCV2TelemetryKeyBeta],
            "which is the fresh event, not the ones that would have refused the batch");
  QON_CHECK(sender.droppedEventCount == 11, "the pruned occurrences are counted as lost");
}

static void TestAnUnusableClockNeverBuildsABatch(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  env.clock.now = 0;
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 2);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.transport.batchCount == 0,
            "a batch stamped with the epoch floor would be refused whole, so none is built");
  QON_CHECK(sender.droppedEventCount == 0, "and nothing is thrown away over it");

  // The clock comes back; the buffered events are stale by then, so they are
  // pruned rather than sent — but the sender is working again.
  env.clock.now = QONRCV2TelemetryObservedAtSeconds * 1000;
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyBeta, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [env settle];
  QON_CHECK(env.transport.batchCount == 1, "a usable clock flushes again");
}

static void TestARefundedBatchIsNeverDroppedForWantOfMapRoom(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  [env.transport scriptResponse:QONRemoteConfigV2TelemetryResponseNotAddressable times:1];
  // Threshold 10, bound 10: the map fills up again while the batch is out.
  QONRemoteConfigV2TelemetrySender *sender = [env makeSenderWithMaximumEntries:10
                                                               flushThreshold:10];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 10; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"batched-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [env settle];
  QON_CHECK(env.transport.batchCount == 1, "the full map flushed");
  QON_CHECK(sender.droppedEventCount == 0, "with nothing dropped so far");

  QONRemoteConfigV2TelemetryRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == 10,
            "the refused batch is back in the buffer, whole, even though the map was full");
  QON_CHECK(sender.droppedEventCount == 0,
            "a refund may never be charged to the bound that stops new events");
}

static void TestAFlushWithoutASessionMakesNoRequest(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  // An install that has never fetched: no session was ever minted for it.
  [env.sessionStore removeSessionForScope:QONRCV2AckScopeA()];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 2);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.gateway.sessionRequests.count == 0,
            "telemetry must never bootstrap a session of its own");
  QON_CHECK(env.gateway.telemetryRequestCount == 0, "and must make no request without one");
  QON_CHECK(sender.droppedEventCount == 0, "nothing is dropped over it");
  QONRemoteConfigV2TelemetryRecord *record = [env telemetryRecordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == 1 && record.events.firstObject.count == 2,
            "the events wait for the read path to establish a session");
}

static void TestA429IsRetryable(void) {
  QONRCV2AckEnvironment *env = [QONRCV2AckEnvironment new];
  [env.gateway scriptTelemetryStatus:429];
  QONRemoteConfigV2TelemetrySender *sender = [env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.scheduler.pendingCount > 0, "a 429 must schedule a retry rather than drop");
  [env.scheduler runAll];
  [env settle];
  QON_CHECK(env.gateway.telemetryRequestCount == 2, "and the retry goes out");
  QON_CHECK(sender.droppedEventCount == 0, "with nothing lost");
  QON_CHECK([env telemetryRecordForScope:QONRCV2AckScopeA()] == nil,
            "the second attempt was accepted, so the buffer is clear");
}

static void TestARetryableFlushIsRetriedAndThenDropped(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  [env.transport scriptResponse:QONRemoteConfigV2TelemetryResponseRetryable times:8];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [env settle];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2TelemetryMaximumAttempts; attempt++) {
    QON_CHECK(env.scheduler.pendingCount > 0, "a retry is scheduled after every failed attempt");
    [env.scheduler runAll];
    [env settle];
  }

  QON_CHECK(env.transport.batchCount == (NSUInteger)QONRemoteConfigV2TelemetryMaximumAttempts,
            "the ladder is bounded");
  QON_CHECK(sender.droppedEventCount == 3, "and the abandoned events are counted, not re-buffered");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()] == nil, "the durable buffer is cleared too");
}

static void TestAnUnaddressableFlushCostsNoRetryBudget(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  [env.transport scriptResponse:QONRemoteConfigV2TelemetryResponseNotAddressable times:1];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(sender.droppedEventCount == 0, "nothing was refused, so nothing was dropped");
  QONRemoteConfigV2TelemetryRecord *record = [env recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(record.events.count == 1 && record.events.firstObject.count == 3,
            "the events are back in the buffer, whole");

  // The next opportunity delivers them, with the full ladder still available.
  [sender noteSuccessfulFetch];
  [env settle];
  QON_CHECK(env.transport.batchCount == 2, "and a later flush sends them");
  QON_CHECK(env.transport.lastBatch.events.firstObject.count == 3, "with the count intact");
}

static void TestObservationsWithoutABoundIdentityAreDropped(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetrySender *sender = [env makeSender];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 5);
  [sender noteSuccessfulFetch];
  [env settle];

  QON_CHECK(env.transport.batchCount == 0,
            "an observation made while nothing is bound belongs to nobody");
  QON_CHECK([env recordForScope:QONRCV2AckScopeA()] == nil, "and is never persisted");
}

static void TestABindDoesNotReSendABatchUnderWay(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  env.transport.hang = YES;
  QONRemoteConfigV2TelemetrySender *sender = [env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [env settle];
  QON_CHECK(env.transport.batchCount == 1, "one batch is on the wire");

  // An identify that does not actually change the identity.
  [sender bindScope:QONRCV2AckScopeA()];
  [sender noteSuccessfulFetch];
  [env settle];
  QON_CHECK(env.transport.batchCount == 1,
            "re-binding the same identity must not double-count the batch in flight");
}

static void TestTheDurableBufferRoundTrips(void) {
  QONRCV2TelemetryEnvironment *env = [QONRCV2TelemetryEnvironment new];
  QONRemoteConfigV2TelemetryStore *store =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:env.storage];
  QONRemoteConfigV2TelemetryEvent *decode = [[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:QONRCV2TelemetryRelease4
               count:7
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds];
  QONRemoteConfigV2TelemetryEvent *keyless = [[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindSnapshotMalformed
          logicalKey:nil
       releaseNumber:0
               count:1
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds];
  QON_CHECK(decode != nil && keyless != nil, "both events are well formed");
  NSArray<QONRemoteConfigV2TelemetryEvent *> *both = @[decode, keyless];
  QONRemoteConfigV2TelemetryRecord *record =
      [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:both];
  QON_CHECK([store storeRecord:record forScope:QONRCV2AckScopeA()], "the buffer is writable");

  QONRemoteConfigV2TelemetryRecord *loaded = [store recordForScope:QONRCV2AckScopeA()];
  QON_CHECK(loaded.events.count == 2, "and reads back whole");
  QON_CHECK([loaded.events.firstObject isEqual:decode], "with the keyed event intact");
  QON_CHECK([loaded.events.lastObject isEqual:keyless], "and the keyless one too");
  QON_CHECK([store recordForScope:QONRCV2AckScopeB()] == nil,
            "another identity's buffer is not this one's");
  QON_CHECK(![[QONRemoteConfigV2TelemetryStore storageKeyForScope:QONRCV2AckScopeA()]
                 containsString:@"anon-uid-a"],
            "and no storage key may carry the identity");

  // A record whose bytes disagree with the schema is untrusted whole.
  env.storage.objects[[QONRemoteConfigV2TelemetryStore storageKeyForScope:QONRCV2AckScopeA()]] =
      @{@"schema_version": @1, @"events": @[@{@"kind": @"not_a_kind"}]};
  QON_CHECK([store recordForScope:QONRCV2AckScopeA()] == nil, "a malformed buffer is discarded");
}

#pragma mark - Client context normalization

/**
 The exact arguments the SDK's enable path passes, in the order it passes them.

 Every field is given a value nothing else could produce, so an argument swapped
 anywhere between `initWithConfig:` and the wire shows up as a field holding
 another field's value rather than as a test that still passes.
 */
static QONRemoteConfigV2ClientContext *EnablePathContext(void) {
  QONRCV2FakeInstallDateProvider *installDate = [QONRCV2FakeInstallDateProvider new];
  installDate.seconds = @1600000000;
  QONRemoteConfigV2DeviceClientContextProvider *provider =
      [QONRemoteConfigV2DeviceClientContextProvider providerWithPlatform:@"iOS"
                                                             appVersion:@"app-1.2.3"
                                                              osVersion:@"os-17.4"
                                                             sdkVersion:@"sdk-6.14.0"
                                                       localeIdentifier:@"en_US@rg=gbzzzz"
                                                            deviceModel:@"iPhone15,2"
                                                    installDateProvider:installDate];
  return [provider currentClientContext];
}

static void TestTheEnablePathProducesEverySevenWireFields(void) {
  NSDictionary *object = [EnablePathContext() JSONObject];

  QON_CHECK([object isEqual:(@{
    // Lower case: a targeting rule must not depend on Apple's brand casing
    // while the Android SDK states a plain "android".
    @"platform": @"ios",
    @"app_version": @"app-1.2.3",
    @"os_version": @"os-17.4",
    @"sdk_version": @"sdk-6.14.0",
    // The keyword suffix is a preference, not a locale.
    @"locale": @"en_US",
    @"device_model": @"iPhone15,2",
    @"device_installed_at": @1600000000,
  })], "the enable path must produce exactly the seven wire fields, unswapped");
}

static void TestALocaleIsReshapedIntoTheTagAndroidStates(void) {
  QONRCV2FakeInstallDateProvider *installDate = [QONRCV2FakeInstallDateProvider new];
  NSArray<NSArray<NSString *> *> *cases = @[
    @[@"en_US@rg=gbzzzz", @"en_US"],
    @[@"en_US@calendar=gregorian;numbers=latn", @"en_US"],
    @[@"en-US", @"en_US"],  // the language-tag spelling Android sends
    @[@"en", @"en"],
    @[@"@rg=gbzzzz", @"UNKNOWN"],  // keywords and no locale at all
    @[@"und", @"UNKNOWN"],
    @[@"", @"UNKNOWN"],
  ];

  for (NSArray<NSString *> *pair in cases) {
    QONRemoteConfigV2DeviceClientContextProvider *provider =
        [QONRemoteConfigV2DeviceClientContextProvider providerWithPlatform:@"iOS"
                                                               appVersion:@"1.2.3"
                                                                osVersion:@"17.4"
                                                               sdkVersion:@"9.9.9"
                                                         localeIdentifier:pair[0]
                                                              deviceModel:@"iPhone15,2"
                                                      installDateProvider:installDate];
    QON_CHECK([[provider currentClientContext].locale isEqualToString:pair[1]],
              "a locale must reach the wire in the shape every SDK states");
  }
}

static void TestAWithheldDeviceFactBecomesAPlaceholderRatherThanNoContext(void) {
  QONRCV2FakeInstallDateProvider *installDate = [QONRCV2FakeInstallDateProvider new];
  QONRemoteConfigV2DeviceClientContextProvider *provider =
      [QONRemoteConfigV2DeviceClientContextProvider providerWithPlatform:nil
                                                             appVersion:nil
                                                              osVersion:@""
                                                             sdkVersion:@"9.9.9"
                                                       localeIdentifier:nil
                                                            deviceModel:nil
                                                    installDateProvider:installDate];
  QONRemoteConfigV2ClientContext *context = [provider currentClientContext];

  // A nil component nils the whole context, and a nil context fails every
  // snapshot request: an app with no CFBundleShortVersionString would lose
  // Remote Config entirely rather than lose one field.
  QON_CHECK(context != nil, "a withheld fact must not take the surface off the air");
  QON_CHECK([context.platform isEqualToString:@"UNKNOWN"], "an absent platform is UNKNOWN");
  QON_CHECK([context.appVersion isEqualToString:@"UNKNOWN"], "an absent app version is UNKNOWN");
  QON_CHECK([context.osVersion isEqualToString:@"UNKNOWN"], "an empty os version is UNKNOWN");
  QON_CHECK([context.locale isEqualToString:@"UNKNOWN"], "an absent locale is UNKNOWN");
  QON_CHECK([context.deviceModel isEqualToString:@"UNKNOWN"], "an absent model is UNKNOWN");
  QON_CHECK([context.sdkVersion isEqualToString:@"9.9.9"], "a stated fact is left alone");
  // The install date is the one omittable field: it is a device fact the
  // gateway ages the user by, not a component it needs present.
  QON_CHECK(context.deviceInstalledAtSeconds == nil, "an unknown install date is omitted");
  QON_CHECK([[context JSONObject] objectForKey:@"device_installed_at"] == nil,
            "and never appears in the body");
}

static void TestOnlyAPositiveWholeSecondCountSeedsTheInstallDate(void) {
  NSArray<NSString *> *refused = @[@"", @"0", @"-1", @"abc", @"17 years", @"1600000000.5",
                                   @" 1600000000"];
  for (NSString *fact in refused) {
    QON_CHECK([QONRemoteConfigV2DeviceInstallDateProvider
                  installDateSecondsFromSystemFact:fact] == nil,
              "anything that is not a positive whole second count seeds nothing");
  }

  QON_CHECK([QONRemoteConfigV2DeviceInstallDateProvider
                installDateSecondsFromSystemFact:nil] == nil,
            "an absent platform fact seeds nothing");
  QON_CHECK([[QONRemoteConfigV2DeviceInstallDateProvider
                 installDateSecondsFromSystemFact:@"1600000000"] isEqualToNumber:@1600000000],
            "a whole second count is read exactly");
}

static void TestABaseURLCarryingAQueryOrFragmentCannotSwallowTheRoute(void) {
  QONRCV2FakeHTTPExecutor *executor = [QONRCV2FakeHTTPExecutor new];
  QONRCV2FakeLocalStorage *storage = [QONRCV2FakeLocalStorage new];
  NSURL *baseURL = [NSURL URLWithString:@"https://gateway.test.example/prefix?tenant=1#frag"];
  QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
       initWithBaseURL:baseURL
          projectToken:QONRCV2TestProjectToken
          httpExecutor:executor
          sessionStore:[[QONRemoteConfigV2GatewaySessionStore alloc] initWithLocalStorage:storage]
  projectIdentityStore:[[QONRemoteConfigV2ProjectIdentityStore alloc]
                            initWithLocalStorage:storage
                                         baseURL:baseURL
                                    projectToken:QONRCV2TestProjectToken]
 clientContextProvider:QONRCV2ContextProvider([QONRCV2FakeInstallDateProvider new])
                 clock:[QONRCV2FakeClock new]
       failureObserver:nil];
  [transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  [executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                   body:QONRCV2BootstrapBody(@"session-token-1", 0)
                                                headers:nil]];

  [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
               completion:^(__unused QONRemoteConfigV2FetchResponse *response) {}];

  // The configuration accepts such a url — it is absolute and addressable — and
  // the transport is what makes it harmless: the path is appended to the base
  // path, and the query and fragment are dropped rather than left to swallow
  // the route.
  QON_CHECK(executor.requests.count >= 1, "the bootstrap must have been attempted");
  QON_CHECK([executor.requests.firstObject.URL.absoluteString
                isEqualToString:@"https://gateway.test.example/prefix/v3/remote-config-v2/session"],
            "a base url carrying a query or fragment must not swallow the route");
}

int main(void) {
  @autoreleasepool {
    TestRequestShapes();
    TestIfNoneMatchForwarded();
    TestExactBytes();
    TestMalformedSuccess();
    TestNotModified();
    TestReBootstrapOnce();
    TestSecondUnauthorized();
    TestUnauthorizedOnFreshSession();
    TestTypedFailures();
    TestSessionScoping();
    TestExpiredSession();
    TestDeviceInstallDate();
    TestContractHardening();
    TestSecretHygiene();
    TestBootstrapEstablishesTheProjectID();
    TestAConflictingReBootstrapIsATypedFailure();
    TestTheLearnedProjectIDSurvivesStoreRecreation();
    TestProjectIdentityIsKeyedWithoutTheIdentity();
    TestProjectIdentityPersistenceAndRange();
    TestAStoredSessionTheLedgerCannotVouchForIsDropped();

    TestAnAckMatchesTheGatewayContractExactly();
    TestADeliveredReleaseIsNeverAckedTwice();
    TestA401ReBootstrapsOnceAndRetriesTheAck();
    TestA401ThatSurvivesTheReBootstrapIsPermanent();
    TestAPermanentRefusalSettlesTheRelease();
    TestA503IsRetriedToTheBoundAndThenDropped();
    TestAnExhaustedLadderIsNotReArmedByARebinding();
    TestAnUnbindAndRebindDoesNotBuyTheSameReleaseANewLadder();
    TestAPartlySpentLadderIsNotRestartedByARebinding();
    TestAnOlderActivationNeverSupersedesANewerOne();
    TestAnOlderReleaseCannotReAckASettledScope();
    TestANewerActivationSupersedesTheQueuedOne();
    TestAPendingAckSurvivesAProcessRestart();
    TestRebindingTheSameIdentityDoesNotReSendAnAckUnderWay();
    TestAnAckIsNeverSentUnderAnotherIdentitysSession();
    TestAnActivationOfAnUnboundScopeIsIgnored();
    TestBindingAnotherIdentityFencesAnAckOnTheWire();
    TestAReleaseNumberThatCouldNeverAddressAnythingIsRefused();

    TestATelemetryBatchMatchesTheGatewayContractExactly();
    TestOnlyDecodeFailuresCarryALogicalKey();
    TestAKeyRuleViolationIsDroppedRatherThanSent();
    TestRepeatedFailuresCoalesceIntoOneEvent();
    TestA400DropsTheBatchPermanently();
    TestATelemetry503IsRetriedToTheBoundAndThenDropped();
    TestA401ReBootstrapsOnceAndKeepsTheSharedSession();
    TestTelemetryIsNeverSentUnderAnotherIdentitysSession();
    TestABufferedBatchSurvivesAProcessRestart();
    TestAFullBatchAndARefilledMapBothSurviveARestart();
    TestABatchNeverStatesMoreEventsThanTheContractAllows();
    TestAFullBufferSplitsAtTheBatchCap();
    TestAFlushIsDueAtTheThresholdAndNotBefore();
    TestTheTickFlushesABufferBelowTheThreshold();
    TestTheCoalescingMapIsBounded();
    TestAnEntryIsKeyedByKindAndKeyOnly();
    TestAReleaseRolloverKeepsOneEntry();
    TestACountSaturatesAtTheContractCap();
    TestAStaleEventIsPrunedInsteadOfPoisoningItsBatch();
    TestAnUnusableClockNeverBuildsABatch();
    TestARefundedBatchIsNeverDroppedForWantOfMapRoom();
    TestAFlushWithoutASessionMakesNoRequest();
    TestA429IsRetryable();
    TestARetryableFlushIsRetriedAndThenDropped();
    TestAnUnaddressableFlushCostsNoRetryBudget();
    TestObservationsWithoutABoundIdentityAreDropped();
    TestABindDoesNotReSendABatchUnderWay();
    TestTheDurableBufferRoundTrips();

    TestTheEnablePathProducesEverySevenWireFields();
    TestALocaleIsReshapedIntoTheTagAndroidStates();
    TestAWithheldDeviceFactBecomesAPlaceholderRatherThanNoContext();
    TestOnlyAPositiveWholeSecondCountSeedsTheInstallDate();
    TestABaseURLCarryingAQueryOrFragmentCannotSwallowTheRoute();

    fprintf(stdout, "QONRemoteConfigV2GatewayTransportHarness: %lu/%lu passed\n",
            (unsigned long)(checks - failures), (unsigned long)checks);
  }
  return failures == 0 ? 0 : 1;
}
