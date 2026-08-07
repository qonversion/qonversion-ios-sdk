#import <XCTest/XCTest.h>

#import "QONRemoteConfigV2GatewayTransportFixtures.h"

@interface QONRemoteConfigV2GatewayTransportTests : XCTestCase

@property (nonatomic, strong) QONRCV2FakeHTTPExecutor *executor;
@property (nonatomic, strong) QONRCV2FakeLocalStorage *storage;
@property (nonatomic, strong) QONRemoteConfigV2GatewaySessionStore *sessionStore;
@property (nonatomic, strong) QONRemoteConfigV2ProjectIdentityStore *projectIdentityStore;
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
  self.projectIdentityStore = [[QONRemoteConfigV2ProjectIdentityStore alloc]
      initWithLocalStorage:self.storage
                   baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
              projectToken:QONRCV2TestProjectToken];
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
  projectIdentityStore:self.projectIdentityStore
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
      initWithSessionToken:token projectID:QONRCV2TestProjectID environment:@"production"
          expiresAtSeconds:0];
  XCTAssertTrue([self.sessionStore storeSession:session forScope:QONRCV2Scope(QONRCV2TestAnonUID)]);
  // A stored session is only reusable while the ledger agrees with it, so a
  // seeded install must carry the id it would have learned.
  XCTAssertNotEqual([self.projectIdentityStore establishProjectID:QONRCV2TestProjectID
                                                         forScope:QONRCV2Scope(QONRCV2TestAnonUID)],
                    QONRemoteConfigV2ProjectIdentityOutcomeConflict);
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
  // Two distinct refusals share that one outcome, so pin each at its own layer.
  XCTAssertNil([[QONRemoteConfigV2GatewaySession alloc]
                   initWithSessionToken:@"session-token-1" projectID:INT64_MAX
                            environment:@"production" expiresAtSeconds:0]);
  XCTAssertEqual([self.projectIdentityStore projectIDForScope:QONRCV2Scope(QONRCV2TestAnonUID)], 0);
  XCTAssertEqual([self.projectIdentityStore establishProjectID:INT64_MAX
                                                      forScope:QONRCV2Scope(QONRCV2TestAnonUID)],
                 QONRemoteConfigV2ProjectIdentityOutcomeUnusable);
  XCTAssertEqual([self.projectIdentityStore establishProjectID:0
                                                      forScope:QONRCV2Scope(QONRCV2TestAnonUID)],
                 QONRemoteConfigV2ProjectIdentityOutcomeUnusable);
}

// A stored session is a token, not an authority on which project answers. Only a
// live bootstrap establishes the id, so a session the ledger cannot vouch for is
// dropped rather than fetched with.
- (void)testAStoredSessionTheLedgerCannotVouchForIsDropped {
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  QONRemoteConfigV2GatewaySession *session = [[QONRemoteConfigV2GatewaySession alloc]
      initWithSessionToken:@"orphan-token" projectID:QONRCV2TestProjectID
               environment:@"production" expiresAtSeconds:0];
  XCTAssertTrue([self.sessionStore storeSession:session forScope:scope]);
  XCTAssertEqual([self.projectIdentityStore projectIDForScope:scope], 0);

  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindSuccess);
  XCTAssertEqual(self.executor.requests.count, 2u);
  XCTAssertEqualObjects(
      QONRCV2Header(self.executor.requests[1], QONRemoteConfigV2GatewaySessionHeader),
      @"session-token-1");
  XCTAssertEqual([self.projectIdentityStore projectIDForScope:scope], QONRCV2TestProjectID);
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
    projectIdentityStore:self.projectIdentityStore
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
  projectIdentityStore:self.projectIdentityStore
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
  projectIdentityStore:self.projectIdentityStore
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

#pragma mark - Learned project identity

// The numeric project_id is not a caller input. The gateway states it in the
// session bootstrap, the SDK learns it there, and everything downstream — the
// envelope expectation included — is built from what was learned.

- (void)testBootstrapEstablishesTheProjectID {
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  XCTAssertEqual([self.projectIdentityStore projectIDForScope:scope], 0);

  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];

  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindSuccess);
  XCTAssertEqual(response.projectID, QONRCV2TestProjectID);
  XCTAssertEqual([self.projectIdentityStore projectIDForScope:scope], QONRCV2TestProjectID);

  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *again = [self fetchWithIfNoneMatch:nil];
  XCTAssertEqual(again.kind, QONRemoteConfigV2FetchResponseKindSuccess);
  XCTAssertEqual(again.projectID, QONRCV2TestProjectID);
  XCTAssertEqual(self.executor.requests.count, 3u);
}

- (void)testAConflictingReBootstrapIsATypedFailure {
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  XCTAssertEqual([self fetchWithIfNoneMatch:nil].kind,
                 QONRemoteConfigV2FetchResponseKindSuccess);

  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse status:401 body:nil headers:nil]];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:QONRCV2BootstrapBodyForProject(@"session-token-2", 0, QONRCV2TestProjectID + 1)
     headers:@{@"Content-Type": @"application/json"}]];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];

  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];
  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqual(response.projectID, 0);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindProjectIdentityConflict));
  XCTAssertEqual([self.projectIdentityStore projectIDForScope:scope], QONRCV2TestProjectID);
  XCTAssertNil([self.sessionStore sessionForScope:scope]);
  XCTAssertEqual(self.executor.requests.count, 4u);
}

- (void)testTheLearnedProjectIDSurvivesStoreRecreation {
  QONRemoteConfigV2Scope *scope = QONRCV2Scope(QONRCV2TestAnonUID);
  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  XCTAssertEqual([self fetchWithIfNoneMatch:nil].kind,
                 QONRemoteConfigV2FetchResponseKindSuccess);

  QONRemoteConfigV2ProjectIdentityStore *reopened =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:self.storage
                       baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                  projectToken:QONRCV2TestProjectToken];
  XCTAssertEqual([reopened projectIDForScope:scope], QONRCV2TestProjectID);
  XCTAssertEqual([reopened establishProjectID:QONRCV2TestProjectID forScope:scope],
                 QONRemoteConfigV2ProjectIdentityOutcomeConfirmed);
  XCTAssertEqual([reopened establishProjectID:QONRCV2TestProjectID + 1 forScope:scope],
                 QONRemoteConfigV2ProjectIdentityOutcomeConflict);
  XCTAssertEqual([reopened projectIDForScope:scope], QONRCV2TestProjectID);
}

- (void)testProjectIdentityIsKeyedWithoutTheIdentity {
  QONRemoteConfigV2Scope *anonymous = QONRCV2Scope(QONRCV2TestAnonUID);
  QONRemoteConfigV2Scope *identified = QONRCV2Scope(@"identified-uid");
  // Deliberate: a project id belongs to the project, not to the user, so a
  // logout and a fresh login must not launder a conflicting id past the check.
  XCTAssertEqualObjects([self.projectIdentityStore storageKeyForScope:anonymous],
                        [self.projectIdentityStore storageKeyForScope:identified]);
  XCTAssertNotEqualObjects([QONRemoteConfigV2GatewaySessionStore storageKeyForScope:anonymous],
                           [QONRemoteConfigV2GatewaySessionStore storageKeyForScope:identified]);

  // A conflict is terminal, so the key must separate what legitimately carries
  // different numeric ids: another gateway, or another project token.
  QONRemoteConfigV2ProjectIdentityStore *otherGateway =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:self.storage
                       baseURL:[NSURL URLWithString:@"https://staging.gateway.test.example/"]
                  projectToken:QONRCV2TestProjectToken];
  QONRemoteConfigV2ProjectIdentityStore *otherToken =
      [[QONRemoteConfigV2ProjectIdentityStore alloc]
          initWithLocalStorage:self.storage
                       baseURL:[NSURL URLWithString:QONRCV2TestBaseURLString]
                  projectToken:@"another-project-token"];
  XCTAssertNotEqualObjects([self.projectIdentityStore storageKeyForScope:anonymous],
                           [otherGateway storageKeyForScope:anonymous]);
  XCTAssertNotEqualObjects([self.projectIdentityStore storageKeyForScope:anonymous],
                           [otherToken storageKeyForScope:anonymous]);
  NSURL *noURL = nil;
  NSString *noToken = nil;
  XCTAssertNil([[QONRemoteConfigV2ProjectIdentityStore alloc]
                   initWithLocalStorage:self.storage baseURL:noURL projectToken:noToken]);

  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  XCTAssertEqual([self fetchWithIfNoneMatch:nil].kind,
                 QONRemoteConfigV2FetchResponseKindSuccess);

  [self.transport updateScope:identified];
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:QONRCV2BootstrapBodyForProject(@"session-token-2", 0, QONRCV2TestProjectID + 1)
     headers:@{@"Content-Type": @"application/json"}]];
  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];
  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindProjectIdentityConflict));
}

- (void)testProjectIdentityPersistenceFailureFailsTheFetch {
  self.storage.ignoreWrites = YES;
  [self enqueueBootstrapWithToken:@"session-token-1"];
  [self enqueueSnapshotSuccessWithBody:QONRCV2NonCanonicalSnapshotBody()];
  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];
  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(
      self.failureKinds.lastObject,
      @(QONRemoteConfigV2TransportFailureKindProjectIdentityPersistenceFailed));
  XCTAssertEqual(self.executor.requests.count, 1u);
}

- (void)testAProjectIDBeyondTheSafeIntegerRangeIsMalformed {
  [self.executor enqueue:[QONRCV2ScriptedHTTPResponse
      status:200
        body:QONRCV2BootstrapBodyForProject(@"session-token-1", 0, INT64_MAX)
     headers:@{@"Content-Type": @"application/json"}]];
  QONRemoteConfigV2FetchResponse *response = [self fetchWithIfNoneMatch:nil];
  XCTAssertEqual(response.kind, QONRemoteConfigV2FetchResponseKindFailure);
  XCTAssertEqualObjects(self.failureKinds.lastObject,
                        @(QONRemoteConfigV2TransportFailureKindBootstrapMalformed));
}

@end

#pragma mark - Activation ack

/**
 The shipped transport under the shipped ack sender.

 The headless mirror of this suite is the ack section of
 QONRemoteConfigV2GatewayTransportHarness.m.
 */
@interface QONRemoteConfigV2ActivationAckTests : XCTestCase
@property (nonatomic, strong) QONRCV2AckEnvironment *env;
@end

@implementation QONRemoteConfigV2ActivationAckTests

- (void)setUp {
  [super setUp];
  self.env = [QONRCV2AckEnvironment new];
}

/** Walks the bounded retry ladder to its end without racing the timer it arms. */
- (void)runRetryLadder {
  [self.env settle];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2ActivationAckMaximumAttempts; attempt++) {
    XCTAssertGreaterThan(self.env.scheduler.pendingCount, 0u,
                         @"a retry must be scheduled after every failed attempt");
    [self.env.scheduler runAll];
    [self.env settle];
  }
}

- (void)testAnAckMatchesTheGatewayContractExactly {
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
  NSURLRequest *ack = self.env.gateway.ackRequests.firstObject;
  XCTAssertEqualObjects(ack.HTTPMethod, @"POST");
  XCTAssertEqualObjects(ack.URL.absoluteString,
                        @"https://gateway.test.example/v3/remote-config-v2/ack");
  XCTAssertEqualObjects(QONRCV2Header(ack, @"Authorization"),
                        [@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]);
  XCTAssertEqualObjects(QONRCV2Header(ack, @"Content-Type"), @"application/json");
  // The ack rides the very session the snapshot was read under.
  XCTAssertEqualObjects(QONRCV2Header(ack, QONRemoteConfigV2GatewaySessionHeader),
                        QONRCV2SeededSessionToken);
  XCTAssertNil(QONRCV2Header(ack, @"If-None-Match"));
  XCTAssertEqualObjects(QONRCV2JSONFromRequest(ack), (@{
    @"release_number": @(QONRCV2AckRelease7),
    @"activated_at": @(QONRCV2AckActivatedAtSeconds),
  }));

  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease7);
  XCTAssertEqual(sender.droppedAckCount, 0);
}

- (void)testADeliveredReleaseIsNeverAckedTwice {
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  // An implicit activation followed by an explicit activate(), and then a rebind.
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
}

- (void)testA401ReBootstrapsExactlyOnceAndRetriesTheAck {
  [self.env.gateway scriptAckStatus:401];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 2u);
  XCTAssertEqual(self.env.gateway.sessionRequests.count, 1u);
  XCTAssertEqualObjects(
      QONRCV2Header(self.env.gateway.ackRequests[0], QONRemoteConfigV2GatewaySessionHeader),
      QONRCV2SeededSessionToken);
  XCTAssertEqualObjects(
      QONRCV2Header(self.env.gateway.ackRequests[1], QONRemoteConfigV2GatewaySessionHeader),
      QONRCV2MintedSessionToken);
  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease7);
  XCTAssertEqual(sender.droppedAckCount, 0);
  // The re-bootstrap is the transport's business, not the sender's retry budget.
  XCTAssertEqual(self.env.scheduler.requestedDelays.count, 0u);
}

- (void)testA401ThatSurvivesTheReBootstrapIsPermanent {
  [self.env.gateway scriptAckStatus:401 times:2];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 2u);
  XCTAssertEqual(sender.droppedAckCount, 1);
  // Permanent is an answer: the release is settled, not left owed.
  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease7);
  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count, 2u);
}

- (void)testAPermanentRefusalSettlesTheReleaseInsteadOfForgettingIt {
  // A gateway that does not serve /ack at all answers every ack with 404.
  [self.env.gateway scriptAckStatus:404 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
  XCTAssertEqual(sender.droppedAckCount, 1);
  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease7);

  [self.env.scheduler runAll];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  // A whole new process over the same durable state must stay silent as well.
  [[self.env makeSender] bindScope:QONRCV2AckScopeA()];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
}

- (void)testA503IsRetriedToTheAttemptBoundAndThenDropped {
  [self.env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self runRetryLadder];

  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts);
  // Half the cap plus jitter, never full-downward jitter.
  XCTAssertEqualObjects(self.env.scheduler.requestedDelays, (@[@750, @1500]));
  XCTAssertEqual(self.env.scheduler.pendingCount, 0u);
  XCTAssertEqual(sender.droppedAckCount, 1);
  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts);
  // Dropped in this process, still owed.
  XCTAssertEqual([self.env recordForScope:QONRCV2AckScopeA()].pending.releaseNumber,
                 QONRCV2AckRelease7);
}

- (void)testAnExhaustedRetryLadderIsNotReArmedByARebinding {
  [self.env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self runRetryLadder];

  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [sender bindScope:QONRCV2AckScopeB()];
  [sender bindScope:QONRCV2AckScopeA()];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts);

  // Only a NEWER release re-arms delivery.
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts + 1);
  XCTAssertEqual(QONRCV2AckReleaseNumber(self.env.gateway.ackRequests.lastObject),
                 QONRCV2AckRelease9);
}

- (void)testAnUnbindAndRebindDoesNotBuyTheSameReleaseANewLadder {
  // The shape every identity change has: the scope is unbound first and bound
  // again afterwards. Neither half may restart a ladder this process spent.
  [self.env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self runRetryLadder];

  for (NSUInteger round = 0; round < 3; round++) {
    [sender bindScope:nil];
    [sender bindScope:QONRCV2AckScopeA()];
    [self.env settle];
  }

  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts);
  XCTAssertEqual(sender.droppedAckCount, 1);
}

- (void)testAPartlySpentLadderIsNotRestartedByARebinding {
  [self.env.gateway scriptAckStatus:503 times:8];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);

  // Rebinding in the middle of a ladder resumes it rather than starting over,
  // so the total stays bounded however often the identity is rebound.
  for (NSUInteger round = 0; round < 5; round++) {
    [sender bindScope:nil];
    [sender bindScope:QONRCV2AckScopeA()];
    [self.env settle];
  }

  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts);
  XCTAssertEqual(sender.droppedAckCount, 1);
}

- (void)testAnOlderActivationNeverSupersedesANewerOne {
  [self.env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [self.env settle];

  // Two reads that raced past each other can report the older release last.
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];
  [self.env.scheduler runAll];
  [self.env settle];

  for (NSURLRequest *request in self.env.gateway.ackRequests) {
    XCTAssertEqual(QONRCV2AckReleaseNumber(request), QONRCV2AckRelease9);
  }
  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease9);
}

- (void)testAnOlderReleaseCannotReAckASettledScope {
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [self.env settle];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  // Settled is a high-water mark: an older release is already answered for.
  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
}

- (void)testANewerActivationSupersedesTheQueuedOne {
  [self.env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  self.env.clock.now = QONRCV2AckLaterActivatedAtSeconds * 1000;
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease9];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 2u);
  XCTAssertEqualObjects(QONRCV2JSONFromRequest(self.env.gateway.ackRequests[1]), (@{
    @"release_number": @(QONRCV2AckRelease9),
    @"activated_at": @(QONRCV2AckLaterActivatedAtSeconds),
  }));
  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease9);
  // The superseded retry never fires, so release 7 is never re-sent.
  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count, 2u);
  XCTAssertEqual(QONRCV2AckReleaseNumber(self.env.gateway.ackRequests[0]), QONRCV2AckRelease7);
  XCTAssertEqual(QONRCV2AckReleaseNumber(self.env.gateway.ackRequests[1]), QONRCV2AckRelease9);
}

- (void)testAPendingAckSurvivesAProcessRestart {
  [self.env.gateway scriptAckStatus:503 times:QONRemoteConfigV2ActivationAckMaximumAttempts];
  QONRemoteConfigV2ActivationAckSender *crashed = [self.env makeSender];
  [crashed bindScope:QONRCV2AckScopeA()];
  [crashed recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self runRetryLadder];
  XCTAssertEqual(crashed.droppedAckCount, 1);

  // A new process: new sender, new queue, new scheduler, a freshly built store
  // over the same durable bytes.
  self.env.scheduler = [QONRCV2ManualScheduler new];
  self.env.clock.now = QONRCV2AckLaterActivatedAtSeconds * 1000;
  QONRemoteConfigV2ActivationAckSender *restarted = [self.env makeSender];
  [restarted bindScope:QONRCV2AckScopeA()];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count,
                 (NSUInteger)QONRemoteConfigV2ActivationAckMaximumAttempts + 1);
  // The ack still reports when the release was ACTIVATED, not when it was
  // finally delivered.
  XCTAssertEqualObjects(QONRCV2JSONFromRequest(self.env.gateway.ackRequests.lastObject), (@{
    @"release_number": @(QONRCV2AckRelease7),
    @"activated_at": @(QONRCV2AckActivatedAtSeconds),
  }));
  QONRemoteConfigV2ActivationAckRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertNil(record.pending);
  XCTAssertEqual(record.settledReleaseNumber, QONRCV2AckRelease7);
  XCTAssertEqual(restarted.droppedAckCount, 0);
}

- (void)testRebindingTheSameIdentityDoesNotReSendAnAckAlreadyUnderWay {
  [self.env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  // An identify that resolves to the identity already bound.
  [sender bindScope:QONRCV2AckScopeA()];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
  XCTAssertEqual(self.env.scheduler.pendingCount, 1u);
  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.ackRequests.count, 2u);
  XCTAssertEqual([self.env recordForScope:QONRCV2AckScopeA()].settledReleaseNumber,
                 QONRCV2AckRelease7);
}

- (void)testAnAckIsNeverSentUnderAnotherIdentitysSession {
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [self.env settle];
  // The transport now addresses another identity than the one that owes the ack.
  [self.env useIdentityScope:QONRCV2AckScopeB()];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 0u);
  XCTAssertEqual(sender.droppedAckCount, 0);
  // Not an attempt: the ack stays queued for the identity that owes it.
  XCTAssertEqual([self.env recordForScope:QONRCV2AckScopeA()].pending.releaseNumber,
                 QONRCV2AckRelease7);
}

- (void)testAnActivationOfAnUnboundScopeIsIgnored {
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [sender bindScope:QONRCV2AckScopeB()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 0u);
  XCTAssertNil([self.env recordForScope:QONRCV2AckScopeA()]);
}

- (void)testBindingAnotherIdentityFencesAnAckThatIsAlreadyOnTheWire {
  [self.env.gateway scriptAckStatus:503];
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:QONRCV2AckRelease7];
  [self.env settle];

  [self.env useIdentityScope:QONRCV2AckScopeB()];
  [sender bindScope:QONRCV2AckScopeB()];
  [self.env settle];
  [self.env.scheduler runAll];
  [self.env settle];

  // The retry the 503 scheduled belongs to the previous identity.
  XCTAssertEqual(self.env.gateway.ackRequests.count, 1u);
  XCTAssertEqual([self.env recordForScope:QONRCV2AckScopeA()].pending.releaseNumber,
                 QONRCV2AckRelease7);
}

- (void)testAReleaseNumberThatCouldNeverAddressAnythingIsRefused {
  QONRemoteConfigV2ActivationAckSender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];

  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:0];
  [sender recordActivationForScope:QONRCV2AckScopeA() releaseNumber:-1];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.ackRequests.count, 0u);
  XCTAssertNil([self.env recordForScope:QONRCV2AckScopeA()]);
}

@end
