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
  QONRemoteConfigV2FetchResponse *headerValidated = [env fetchWithIfNoneMatch:nil];
  QON_CHECK(headerValidated.kind == QONRemoteConfigV2FetchResponseKindNotModified,
            "304 kind from header");
  QON_CHECK([headerValidated.strongETag isEqualToString:QONRCV2TestStrongETag],
            "304 validator from header");
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
  QON_CHECK([[env.sessionStore sessionForScope:anonymous].sessionToken
                isEqualToString:@"anon-token"], "anonymous token untouched");

  NSString *anonymousKey = [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:anonymous];
  NSString *identifiedKey = [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:identified];
  QON_CHECK(![anonymousKey isEqualToString:identifiedKey], "scoped storage keys differ");
  env.storage.objects[identifiedKey] = env.storage.objects[anonymousKey];
  QON_CHECK([env.sessionStore sessionForScope:identified] == nil,
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

static void TestSecretHygiene(void) {
  QONRemoteConfigV2GatewaySession *session = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"super-secret-token" projectID:42 environment:@"production"
          expiresAtSeconds:0];
  QON_CHECK(![session.description containsString:@"super-secret-token"],
            "description hides the token");
  QON_CHECK(![session.debugDescription containsString:@"super-secret-token"],
            "debugDescription hides the token");
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
    TestSecretHygiene();

    fprintf(stdout, "QONRemoteConfigV2GatewayTransportHarness: %lu/%lu passed\n",
            (unsigned long)(checks - failures), (unsigned long)checks);
  }
  return failures == 0 ? 0 : 1;
}
