#import <XCTest/XCTest.h>

#import "QONRemoteConfigV2GatewayTransportFixtures.h"

@interface QONRemoteConfigV2GatewayTransportTests : XCTestCase

@property (nonatomic, strong) QONRCV2FakeHTTPExecutor *executor;
@property (nonatomic, strong) QONRCV2FakeLocalStorage *storage;
@property (nonatomic, strong) QONRemoteConfigV2GatewaySessionStore *sessionStore;
@property (nonatomic, strong) QONRCV2FakeClock *clock;
@property (nonatomic, strong) QONRCV2FakeInstallDateProvider *installDateProvider;
@property (nonatomic, strong) QONRemoteConfigV2GatewayTransport *transport;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *failureKinds;
@property (nonatomic, strong) NSMutableArray *failureStatusCodes;

@end

@implementation QONRemoteConfigV2GatewayTransportTests

- (void)setUp {
  [super setUp];
  self.executor = [QONRCV2FakeHTTPExecutor new];
  self.storage = [QONRCV2FakeLocalStorage new];
  self.sessionStore = [[QONRemoteConfigV2GatewaySessionStore alloc] initWithLocalStorage:self.storage];
  self.clock = [QONRCV2FakeClock new];
  self.clock.now = 1000000000000;
  self.installDateProvider = [QONRCV2FakeInstallDateProvider new];
  self.installDateProvider.seconds = @1600000000;
  self.failureKinds = [NSMutableArray new];
  self.failureStatusCodes = [NSMutableArray new];

  __weak typeof(self) weakSelf = self;
  self.transport = [[QONRemoteConfigV2GatewayTransport alloc]
       initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
          projectToken:QONRCV2TestProjectToken
          httpExecutor:self.executor
          sessionStore:self.sessionStore
 clientContextProvider:QONRCV2ContextProvider(self.installDateProvider)
                 clock:self.clock
       failureObserver:^(QONRemoteConfigV2TransportFailureKind kind, NSNumber *statusCode) {
    [weakSelf.failureKinds addObject:@(kind)];
    [weakSelf.failureStatusCodes addObject:statusCode ?: NSNull.null];
  }];
  [self.transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
}

#pragma mark - Helpers

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
  XCTAssertTrue([self.sessionStore storeSession:session forScope:QONRCV2Scope(QONRCV2TestAnonUID)]);
}

- (void)enqueueBootstrapWithToken:(NSString *)token {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                        body:QONRCV2BootstrapBody(token, 0)
                                                     headers:@{@"Content-Type": @"application/json"}]];
}

- (void)enqueueSnapshotSuccessWithBody:(NSData *)body {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                        body:body
                                                     headers:@{@"ETag": QONRCV2TestStrongETag}]];
}

#pragma mark - Request shape

- (void)testBootstrapRequestShapeMatchesGatewayContract {
  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(self.executor.requests.count, 2u);
  NSURLRequest *bootstrap = self.executor.requests[0];
  XCTAssertEqualObjects(bootstrap.URL.absoluteString,
                        @"https://gateway.test.example/v3/remote-config-v2/session");
  XCTAssertEqualObjects(bootstrap.HTTPMethod, @"POST");
  XCTAssertEqualObjects(QONRCV2Header(bootstrap, @"Authorization"),
                        [@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]);
  XCTAssertEqualObjects(QONRCV2Header(bootstrap, @"Content-Type"), @"application/json");
  XCTAssertNil(QONRCV2Header(bootstrap, QONRemoteConfigV2GatewaySessionHeader));
  XCTAssertNil(QONRCV2Header(bootstrap, @"If-None-Match"));
  XCTAssertEqualObjects(QONRCV2JSONFromRequest(bootstrap), @{@"user_uid": QONRCV2TestAnonUID});
}

- (void)testSnapshotRequestShapeMatchesGatewayContract {
  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  [self fetchWithIfNoneMatch:nil];

  NSURLRequest *snapshot = self.executor.requests[1];
  XCTAssertEqualObjects(snapshot.URL.absoluteString,
                        @"https://gateway.test.example/v3/remote-config-v2/snapshot");
  XCTAssertEqualObjects(snapshot.HTTPMethod, @"POST");
  XCTAssertEqualObjects(QONRCV2Header(snapshot, @"Authorization"),
                        [@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]);
  XCTAssertEqualObjects(QONRCV2Header(snapshot, QONRemoteConfigV2GatewaySessionHeader),
                        @"session-token-1");
  XCTAssertNil(QONRCV2Header(snapshot, @"If-None-Match"));

  NSDictionary *body = QONRCV2JSONFromRequest(snapshot);
  XCTAssertEqualObjects(body.allKeys, @[@"client_context"]);
  XCTAssertEqualObjects(body[@"client_context"], (@{
    @"platform": @"iOS",
    @"app_version": @"1.2.3",
    @"os_version": @"17.4",
    @"sdk_version": @"9.9.9",
    @"locale": @"en_US",
    @"device_model": @"iPhone15,2",
    @"device_installed_at": @1600000000,
  }));
}

- (void)testSnapshotForwardsIfNoneMatchExactly {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304 body:nil headers:nil]];

  [self fetchWithIfNoneMatch:QONRCV2TestStrongETag];

  XCTAssertEqual(self.executor.requests.count, 1u);
  XCTAssertEqualObjects(QONRCV2Header(self.executor.requests[0], @"If-None-Match"),
                        QONRCV2TestStrongETag);
}

#pragma mark - Success and 304

- (void)testSuccessDeliversExactResponseBytesAndStrongETag {
  NSData *body = QONRCV2NonCanonicalSnapshotBody();
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:body];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindSuccess);
  XCTAssertEqualObjects(response.body, body);
  XCTAssertTrue(QONRCV2DataIdenticalBytes(response.body, body));
  XCTAssertEqualObjects(response.strongETag, QONRCV2TestStrongETag);
}

- (void)testSuccessWithoutStrongETagIsTypedMalformedFailure {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:200
                                                        body:QONRCV2NonCanonicalSnapshotBody()
                                                     headers:@{@"ETag": @"W/\"weak\""}]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindSnapshotMalformed));
}

- (void)testNotModifiedKeepsValidatorFromResponseOrRequest {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:QONRCV2TestStrongETag];
  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindNotModified);
  XCTAssertNil(response.body);
  XCTAssertEqualObjects(response.strongETag, QONRCV2TestStrongETag);

  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304
                                                        body:nil
                                                     headers:@{@"ETag": QONRCV2TestStrongETag}]];
  QONRemoteConfigV2FetchResponse *headerValidated =
      [self fetchWithIfNoneMatch:@"\"0000000000000000000000000000000000000000000000000000000000000002\""];
  XCTAssertEqual(headerValidated.kind, QONRemoteConfigV2FetchResponseKindNotModified);
  XCTAssertEqualObjects(headerValidated.strongETag, QONRCV2TestStrongETag);
}

#pragma mark - Unauthorized recovery

- (void)testUnauthorizedSnapshotReBootstrapsOnceAndRetries {
  NSData *body = QONRCV2NonCanonicalSnapshotBody();
  [self seedStoredSessionWithToken:@"stale-token"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];
  [self enqueueBootstrapWithToken:@"fresh-token"];
  [self enqueueSnapshotSuccessWithBody:body];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindSuccess);
  XCTAssertTrue(QONRCV2DataIdenticalBytes(response.body, body));
  XCTAssertEqual(self.executor.requests.count, 3u);
  XCTAssertEqualObjects(QONRCV2Header(self.executor.requests[0],
                                      QONRemoteConfigV2GatewaySessionHeader), @"stale-token");
  XCTAssertEqualObjects(self.executor.requests[1].URL.path, @"/v3/remote-config-v2/session");
  XCTAssertEqualObjects(QONRCV2Header(self.executor.requests[2],
                                      QONRemoteConfigV2GatewaySessionHeader), @"fresh-token");
  QONRemoteConfigV2GatewaySession *stored =
      [self.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  XCTAssertEqualObjects(stored.sessionToken, @"fresh-token");
}

- (void)testSecondUnauthorizedIsTypedFailureWithoutLoops {
  [self seedStoredSessionWithToken:@"stale-token"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];
  [self enqueueBootstrapWithToken:@"fresh-token"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(response.statusCode, @401);
  XCTAssertEqual(self.executor.requests.count, 3u);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindSnapshotUnauthorized));
  XCTAssertNil([self.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)]);
}

- (void)testUnauthorizedOnFreshlyBootstrappedSessionDoesNotBootstrapAgain {
  [self enqueueBootstrapWithToken:@"fresh-token"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(response.statusCode, @401);
  XCTAssertEqual(self.executor.requests.count, 2u);
}

#pragma mark - Typed failures

- (void)testSnapshotNotFoundIsTypedFailure {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:404 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(response.statusCode, @404);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindSnapshotNotFound));
}

- (void)testSnapshotUnavailableIsTypedFailureWithRetryAfter {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:503
                                                        body:nil
                                                     headers:@{@"Retry-After": @"12"}]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(response.statusCode, @503);
  XCTAssertEqualObjects(response.retryAfterMilliseconds, @12000);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindSnapshotUnavailable));
}

- (void)testBootstrapFailuresAreTypedAndSkipSnapshot {
  NSArray *cases = @[
    @[@401, @(QONRemoteConfigV2TransportFailureKindBootstrapUnauthorized)],
    @[@404, @(QONRemoteConfigV2TransportFailureKindBootstrapNotFound)],
    @[@503, @(QONRemoteConfigV2TransportFailureKindBootstrapUnavailable)],
  ];
  for (NSArray *testCase in cases) {
    [self setUp];
    [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:[testCase[0] integerValue]
                                                          body:nil
                                                       headers:nil]];

    QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

    XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
    XCTAssertEqualObjects(response.statusCode, testCase[0]);
    XCTAssertEqual(self.executor.requests.count, 1u);
    XCTAssertEqualObjects(self.failureKinds.lastObject, testCase[1]);
  }
}

- (void)testMalformedBootstrapBodyIsTypedFailure {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:[@"{\"session_token\":\"\",\"project_id\":42,\"environment\":\"production\"}"
                 dataUsingEncoding:NSUTF8StringEncoding]
     headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindBootstrapMalformed));
}

- (void)testBootstrapForAnotherEnvironmentIsRejected {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:[@"{\"session_token\":\"t\",\"project_id\":42,\"environment\":\"sandbox\"}"
                 dataUsingEncoding:NSUTF8StringEncoding]
     headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqual(self.executor.requests.count, 1u);
  XCTAssertNil([self.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)]);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindBootstrapMalformed));
}

- (void)testBootstrapTokenThatCannotBeSentAsAHeaderIsRejected {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:[@"{\"session_token\":\"bad\\r\\ntoken\",\"project_id\":42,"
               "\"environment\":\"production\"}" dataUsingEncoding:NSUTF8StringEncoding]
     headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqual(self.executor.requests.count, 1u);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindBootstrapMalformed));
}

- (void)testZeroRetryAfterDoesNotDefeatBackoff {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:503
                                                        body:nil
                                                     headers:@{@"Retry-After": @"0"}]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqualObjects(response.statusCode, @503);
  XCTAssertNil(response.retryAfterMilliseconds);
}

- (void)testNotModifiedWithoutAValidatorIsMalformed {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:304 body:nil headers:nil]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindSnapshotMalformed));
}

- (void)testRoutePathSurvivesAwkwardBaseURLs {
  NSArray<NSArray<NSString *> *> *cases = @[
    @[@"https://gateway.test.example", @"https://gateway.test.example/v3/remote-config-v2/session"],
    @[@"https://gateway.test.example/api",
      @"https://gateway.test.example/api/v3/remote-config-v2/session"],
    @[@"https://gateway.test.example/?trace=1",
      @"https://gateway.test.example/v3/remote-config-v2/session"],
    @[@"https://gateway.test.example/api#frag",
      @"https://gateway.test.example/api/v3/remote-config-v2/session"],
  ];
  for (NSArray<NSString *> *testCase in cases) {
    QONRCV2FakeHTTPExecutor *executor = [QONRCV2FakeHTTPExecutor new];
    QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
         initWithBaseURL:[NSURL URLWithString:testCase[0]]
            projectToken:QONRCV2TestProjectToken
            httpExecutor:executor
            sessionStore:self.sessionStore
   clientContextProvider:QONRCV2ContextProvider(self.installDateProvider)
                   clock:self.clock
         failureObserver:nil];
    [transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
    [executor enqueue:[QONRCV2ScriptedHTTPResponse status:503 body:nil headers:nil]];

    [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
                 completion:^(QONRemoteConfigV2FetchResponse *response) {}];

    XCTAssertEqual(executor.requests.count, 1u);
    XCTAssertEqualObjects(executor.requests[0].URL.absoluteString, testCase[1]);
  }
}

- (void)testProjectTokenThatCannotBeSentAsAHeaderIsRefusedAtConstruction {
  XCTAssertNil([[QONRemoteConfigV2GatewayTransport alloc]
       initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
          projectToken:@"bad\r\ntoken"
          httpExecutor:self.executor
          sessionStore:self.sessionStore
 clientContextProvider:QONRCV2ContextProvider(self.installDateProvider)
                 clock:self.clock
       failureObserver:nil]);
}

- (void)testTransportErrorIsRetryableFailureWithoutStatusCode {
  [self seedStoredSessionWithToken:@"session-token-1"];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse transportError]];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertNil(response.statusCode);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindSnapshotTransport));
}

- (void)testUnboundScopeFailsWithoutNetworking {
  [self.transport updateScope:nil];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqual(self.executor.requests.count, 0u);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindNotConfigured));
}

#pragma mark - Session scoping

- (void)testSessionIsPersistedPerScopeAndNeverReusedAcrossIdentities {
  [self enqueueBootstrapWithToken:@"anon-token"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [self fetchWithIfNoneMatch:nil];

  QONRemoteConfigV2Scope *anonymous = QONRCV2Scope(QONRCV2TestAnonUID);
  QONRemoteConfigV2Scope *identified = QONRCV2Scope(@"identified-uid");
  XCTAssertEqualObjects([self.sessionStore sessionForScope:anonymous].sessionToken, @"anon-token");
  XCTAssertNil([self.sessionStore sessionForScope:identified]);

  [self.transport updateScope:identified];
  [self enqueueBootstrapWithToken:@"identified-token"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(self.executor.requests.count, 4u);
  XCTAssertEqualObjects(self.executor.requests[2].URL.path, @"/v3/remote-config-v2/session");
  XCTAssertEqualObjects(QONRCV2JSONFromRequest(self.executor.requests[2]),
                        @{@"user_uid": @"identified-uid"});
  XCTAssertEqualObjects(QONRCV2Header(self.executor.requests[3],
                                      QONRemoteConfigV2GatewaySessionHeader), @"identified-token");
  XCTAssertEqualObjects([self.sessionStore sessionForScope:identified].sessionToken,
                        @"identified-token");
  XCTAssertNil([self.sessionStore sessionForScope:anonymous]);
}

- (void)testIdentityChangeDropsTheRetiredSessionImmediately {
  [self seedStoredSessionWithToken:@"anon-token"];
  QONRemoteConfigV2Scope *anonymous = QONRCV2Scope(QONRCV2TestAnonUID);

  [self.transport updateScope:QONRCV2Scope(@"identified-uid")];

  XCTAssertNil([self.sessionStore sessionForScope:anonymous]);
  XCTAssertEqual(self.executor.requests.count, 0u);
}

- (void)testRebindingTheSameScopeKeepsTheSession {
  [self seedStoredSessionWithToken:@"anon-token"];

  [self.transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];

  XCTAssertEqualObjects([self.sessionStore sessionForScope:QONRCV2Scope(QONRCV2TestAnonUID)]
                            .sessionToken, @"anon-token");
}

- (void)testExpiredSessionTriggersBootstrapBeforeSnapshot {
  QONRemoteConfigV2GatewaySession *expired = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"expired-token" projectID:42 environment:@"production"
          expiresAtSeconds:self.clock.now / 1000 - 1];
  XCTAssertTrue([self.sessionStore storeSession:expired forScope:QONRCV2Scope(QONRCV2TestAnonUID)]);
  [self enqueueBootstrapWithToken:@"fresh-token"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindSuccess);
  XCTAssertEqual(self.executor.requests.count, 2u);
  XCTAssertEqualObjects(QONRCV2Header(self.executor.requests[1],
                                      QONRemoteConfigV2GatewaySessionHeader), @"fresh-token");
}

- (void)testStoredSessionIsNotReadableUnderAnotherScope {
  [self seedStoredSessionWithToken:@"anon-token"];
  NSString *anonymousKey =
      [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  NSString *identifiedKey =
      [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:QONRCV2Scope(@"identified-uid")];
  XCTAssertNotEqualObjects(anonymousKey, identifiedKey);

  // Even a copied payload cannot be replayed under another identity.
  self.storage.objects[identifiedKey] = self.storage.objects[anonymousKey];
  XCTAssertNil([self.sessionStore sessionForScope:QONRCV2Scope(@"identified-uid")]);
}

#pragma mark - Device install date

- (void)testDeviceInstallDateSurvivesSimulatedLogout {
  QONRCV2FakeLocalStorage *deviceStorage = [QONRCV2FakeLocalStorage new];
  QONRemoteConfigV2DeviceInstallDateProvider *provider =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc] initWithLocalStorage:deviceStorage
                                                     systemInstallDateSeconds:@1500000000
                                                                        clock:self.clock];
  NSNumber *before = [provider deviceInstalledAtSeconds];
  XCTAssertEqualObjects(before, @1500000000);

  // Simulated logout: every identity-scoped record is dropped and a new
  // anonymous identity is issued. The device fact must not move.
  NSString *deviceKey = QONRemoteConfigV2DeviceInstallDateStorageKey;
  for (NSString *key in deviceStorage.objects.allKeys) {
    if (![key isEqualToString:deviceKey]) [deviceStorage removeObjectForKey:key];
  }
  QONRemoteConfigV2DeviceInstallDateProvider *afterLogout =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc] initWithLocalStorage:deviceStorage
                                                     systemInstallDateSeconds:@1900000000
                                                                        clock:self.clock];
  XCTAssertEqualObjects([afterLogout deviceInstalledAtSeconds], before);

  XCTAssertEqual(deviceStorage.objects.count, 1u);
  XCTAssertNotNil(deviceStorage.objects[deviceKey]);
  XCTAssertFalse([deviceKey containsString:QONRCV2TestAnonUID]);
}

- (void)testDeviceInstallDateReachesTheSnapshotBodyAcrossLogout {
  QONRCV2FakeLocalStorage *deviceStorage = [QONRCV2FakeLocalStorage new];
  QONRemoteConfigV2DeviceInstallDateProvider *provider =
      [[QONRemoteConfigV2DeviceInstallDateProvider alloc] initWithLocalStorage:deviceStorage
                                                     systemInstallDateSeconds:@1500000000
                                                                        clock:self.clock];
  QONRemoteConfigV2GatewayTransport *transport = [[QONRemoteConfigV2GatewayTransport alloc]
       initWithBaseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
          projectToken:QONRCV2TestProjectToken
          httpExecutor:self.executor
          sessionStore:self.sessionStore
 clientContextProvider:QONRCV2ContextProvider(provider)
                 clock:self.clock
       failureObserver:nil];

  [transport updateScope:QONRCV2Scope(QONRCV2TestAnonUID)];
  [self enqueueBootstrapWithToken:@"anon-token"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
               completion:^(QONRemoteConfigV2FetchResponse *response) {}];

  [transport updateScope:QONRCV2Scope(@"anon-uid-after-logout")];
  [self enqueueBootstrapWithToken:@"post-logout-token"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  [transport fetchRequest:[[QONRemoteConfigV2FetchRequest alloc] initWithIfNoneMatch:nil]
               completion:^(QONRemoteConfigV2FetchResponse *response) {}];

  NSDictionary *before = QONRCV2JSONFromRequest(self.executor.requests[1])[@"client_context"];
  NSDictionary *after = QONRCV2JSONFromRequest(self.executor.requests[3])[@"client_context"];
  XCTAssertEqualObjects(before[@"device_installed_at"], @1500000000);
  XCTAssertEqualObjects(after[@"device_installed_at"], before[@"device_installed_at"]);
}

- (void)testClientContextOmitsUnknownInstallDate {
  self.installDateProvider.seconds = nil;
  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  [self fetchWithIfNoneMatch:nil];

  NSDictionary *context = QONRCV2JSONFromRequest(self.executor.requests[1])[@"client_context"];
  XCTAssertEqual(context.count, 6u);
  XCTAssertNil(context[@"device_installed_at"]);
}

#pragma mark - Secret hygiene

- (void)testSessionDescriptionNeverExposesToken {
  QONRemoteConfigV2GatewaySession *session = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"super-secret-token" projectID:42 environment:@"production"
          expiresAtSeconds:0];
  XCTAssertFalse([session.description containsString:@"super-secret-token"]);
  XCTAssertFalse([session.debugDescription containsString:@"super-secret-token"]);
}

@end
