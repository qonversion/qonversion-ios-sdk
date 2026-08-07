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
    _projectIdentityStore =
        [[QONRemoteConfigV2ProjectIdentityStore alloc] initWithLocalStorage:_storage];
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
      initWithSessionToken:token projectID:42 environment:@"production" expiresAtSeconds:0];
  QON_CHECK([self.sessionStore storeSession:session forScope:QONRCV2Scope(QONRCV2TestAnonUID)],
            "seeded session stored");
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
    @"platform": @"iOS", @"app_version": @"1.2.3", @"os_version": @"17.4",
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
      [[QONRemoteConfigV2ProjectIdentityStore alloc] initWithLocalStorage:env.storage];
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
  // Deliberate: a project id belongs to the project, not to the user, so a
  // logout and a fresh login must not launder a conflicting id past the check.
  QON_CHECK([[QONRemoteConfigV2ProjectIdentityStore storageKeyForScope:anonymous]
                isEqualToString:
                    [QONRemoteConfigV2ProjectIdentityStore storageKeyForScope:identified]],
            "two identities of one project must share the project identity key");
  QON_CHECK(![[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:anonymous]
                isEqualToString:[QONRemoteConfigV2GatewaySessionStore storageKeyForScope:identified]],
            "session tokens must still be keyed per identity");

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

    fprintf(stdout, "QONRemoteConfigV2GatewayTransportHarness: %lu/%lu passed\n",
            (unsigned long)(checks - failures), (unsigned long)checks);
  }
  return failures == 0 ? 0 : 1;
}
