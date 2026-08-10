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

#pragma mark - Client telemetry, gateway route

@interface QONRemoteConfigV2TelemetryRouteTests : XCTestCase
@property (nonatomic, strong) QONRCV2AckEnvironment *env;
@end

@implementation QONRemoteConfigV2TelemetryRouteTests

- (void)setUp {
  [super setUp];
  self.env = [QONRCV2AckEnvironment new];
}

/** Walks a telemetry retry ladder to its bound, one manual tick per attempt. */
- (void)runTelemetryRetryLadder {
  [self.env settle];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2TelemetryMaximumAttempts; attempt++) {
    XCTAssertGreaterThan(self.env.scheduler.pendingCount, 0u);
    [self.env.scheduler runAll];
    [self.env settle];
  }
}

- (void)testATelemetryBatchMatchesTheGatewayContractExactly {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 1u);
  NSURLRequest *request = self.env.gateway.telemetryRequests.firstObject;
  XCTAssertEqualObjects(request.HTTPMethod, @"POST");
  XCTAssertEqualObjects(request.URL.absoluteString,
                        @"https://gateway.test.example/v3/remote-config-v2/telemetry");
  XCTAssertEqualObjects(QONRCV2Header(request, @"Authorization"),
                        [@"Bearer " stringByAppendingString:QONRCV2TestProjectToken]);
  XCTAssertEqualObjects(QONRCV2Header(request, @"Content-Type"), @"application/json");
  // The batch must ride the very session the snapshot was read under.
  XCTAssertEqualObjects(QONRCV2Header(request, QONRemoteConfigV2GatewaySessionHeader),
                        QONRCV2SeededSessionToken);
  XCTAssertNil(QONRCV2Header(request, @"If-None-Match"));
  XCTAssertEqualObjects(QONRCV2JSONFromRequest(request), (@{
    @"events": @[@{
      @"kind": @"decode_failure",
      @"logical_key": QONRCV2TelemetryKeyAlpha,
      @"release_number": @(QONRCV2TelemetryRelease4),
      @"count": @3,
      @"last_occurred_at": @(QONRCV2TelemetryObservedAtSeconds),
    }],
  }));
  XCTAssertNil([self.env telemetryRecordForScope:QONRCV2AckScopeA()]);
  XCTAssertEqual(sender.droppedEventCount, 0);
}

- (void)testOnlyDecodeFailuresCarryALogicalKey {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  [sender recordKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:nil
       releaseNumber:0];
  [sender noteSuccessfulFetch];
  [self.env settle];

  NSDictionary *event = QONRCV2TelemetryOnlyEvent(self.env.gateway.telemetryRequests.firstObject);
  XCTAssertEqualObjects(event[@"kind"], @"read_before_activate");
  XCTAssertNil(event[@"logical_key"]);
  XCTAssertEqualObjects(event[@"release_number"], @0);
}

- (void)testAKeyRuleViolationIsDroppedRatherThanSent {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  // A decode failure without a key, a keyless kind with one, and a key carrying
  // a control byte: the gateway would reject the whole batch any of them landed in.
  [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure logicalKey:nil releaseNumber:1];
  [sender recordKind:QONRemoteConfigV2TelemetryKindImplicitActivation
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:1];
  [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:@"control\tcharacter"
       releaseNumber:1];
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 0u);
  XCTAssertEqual(sender.droppedEventCount, 3);
}

- (void)testRepeatedFailuresCoalesceIntoOneEvent {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 500);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 1u);
  NSDictionary *event = QONRCV2TelemetryOnlyEvent(self.env.gateway.telemetryRequests.firstObject);
  XCTAssertEqualObjects(event[@"count"], @500);
}

- (void)testA400DropsTheBatchPermanently {
  [self.env.gateway scriptTelemetryStatus:400 times:8];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 2);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 1u);
  XCTAssertEqual(self.env.scheduler.pendingCount, 0u);
  XCTAssertEqual(sender.droppedEventCount, 2);
  // Gone from disk too, so no restart can re-offer bytes the gateway refused.
  XCTAssertNil([self.env telemetryRecordForScope:QONRCV2AckScopeA()]);
}

- (void)testA503IsRetriedToTheBoundAndThenDropped {
  [self.env.gateway scriptTelemetryStatus:503 times:8];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [self runTelemetryRetryLadder];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount,
                 (NSUInteger)QONRemoteConfigV2TelemetryMaximumAttempts);
  XCTAssertEqual(sender.droppedEventCount, 1);
  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.telemetryRequestCount,
                 (NSUInteger)QONRemoteConfigV2TelemetryMaximumAttempts);
}

- (void)testA401ReBootstrapsOnceAndKeepsTheSharedSession {
  [self.env.gateway scriptTelemetryStatus:401];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.sessionRequests.count, 1u);
  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 2u);
  XCTAssertEqualObjects(QONRCV2Header(self.env.gateway.telemetryRequests.lastObject,
                                      QONRemoteConfigV2GatewaySessionHeader),
                        QONRCV2MintedSessionToken);
  // A 401 here may never leave the config read path without a session.
  XCTAssertNotNil([self.env.sessionStore sessionForScope:QONRCV2AckScopeA()]);
  XCTAssertEqual(sender.droppedEventCount, 0);
}

- (void)testTelemetryIsNeverSentUnderAnotherIdentitysSession {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [self.env useIdentityScope:QONRCV2AckScopeB()];
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 0u);
  XCTAssertEqual([self.env telemetryRecordForScope:QONRCV2AckScopeA()].events.count, 1u);
}

- (void)testABufferedBatchSurvivesAProcessRestart {
  self.env.gateway.hangTelemetry = YES;
  QONRemoteConfigV2TelemetrySender *first = [self.env makeTelemetrySender];
  [first bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(first, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 4);
  [first noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 1u);
  QONRemoteConfigV2TelemetryRecord *record = [self.env telemetryRecordForScope:QONRCV2AckScopeA()];
  XCTAssertEqual(record.events.count, 1u);
  XCTAssertEqual(record.events.firstObject.count, 4);

  // A new process over the same disk: the batch is still owed.
  self.env.gateway.hangTelemetry = NO;
  QONRemoteConfigV2TelemetrySender *second = [self.env makeTelemetrySender];
  [second bindScope:QONRCV2AckScopeA()];
  [second noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 2u);
  NSDictionary *event = QONRCV2TelemetryOnlyEvent(self.env.gateway.telemetryRequests.lastObject);
  XCTAssertEqualObjects(event[@"count"], @4);
  XCTAssertNil([self.env telemetryRecordForScope:QONRCV2AckScopeA()]);
}

/**
 The worst case the durable record has to hold: a full batch on the wire AND a
 map that filled up again behind it.
 */
- (void)testAFullBatchAndARefilledMapBothSurviveARestart {
  self.env.gateway.hangTelemetry = YES;
  // The threshold is raised out of the way so the test, not the buffer, decides
  // when the batch leaves.
  QONRemoteConfigV2TelemetrySender *first = [self.env makeTelemetrySenderWithFlushThreshold:1000];
  [first bindScope:QONRCV2AckScopeA()];
  NSUInteger total = QONRemoteConfigV2TelemetryMaximumBatchEntries +
      QONRemoteConfigV2TelemetryMaximumEntries;
  for (NSUInteger index = 0; index < QONRemoteConfigV2TelemetryMaximumBatchEntries; index++) {
    [first recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
           logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
        releaseNumber:QONRCV2TelemetryRelease4];
  }
  [first noteSuccessfulFetch];
  [self.env settle];
  for (NSUInteger index = QONRemoteConfigV2TelemetryMaximumBatchEntries; index < total; index++) {
    [first recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
           logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
        releaseNumber:QONRCV2TelemetryRelease4];
  }
  [self.env settle];

  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 1u);
  XCTAssertEqual(QONRCV2TelemetryEvents(self.env.gateway.telemetryRequests.firstObject).count,
                 QONRemoteConfigV2TelemetryMaximumBatchEntries);
  // The record holds the batch in flight AND the map behind it.
  XCTAssertEqual([self.env telemetryRecordForScope:QONRCV2AckScopeA()].events.count, total);
  XCTAssertEqual(first.droppedEventCount, 0);

  // A new process over the same disk delivers every one of them.
  self.env.gateway.hangTelemetry = NO;
  QONRemoteConfigV2TelemetrySender *second = [self.env makeTelemetrySender];
  [second bindScope:QONRCV2AckScopeA()];
  for (NSUInteger pass = 0; pass < 8; pass++) {
    [second noteSuccessfulFetch];
    [self.env settle];
  }
  NSMutableSet<NSString *> *keys = [NSMutableSet new];
  for (NSURLRequest *request in self.env.gateway.telemetryRequests) {
    for (NSDictionary *event in QONRCV2TelemetryEvents(request)) {
      [keys addObject:event[@"logical_key"]];
    }
  }
  XCTAssertEqual(keys.count, total);
  XCTAssertNil([self.env telemetryRecordForScope:QONRCV2AckScopeA()]);
}

- (void)testAFlushWithoutASessionMakesNoRequest {
  // An install that has never fetched: no session was ever minted for it.
  [self.env.sessionStore removeSessionForScope:QONRCV2AckScopeA()];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 2);
  [sender noteSuccessfulFetch];
  [self.env settle];

  // Telemetry must never bootstrap a session of its own — it has a 30 s tick,
  // and the config read path owns session establishment.
  XCTAssertEqual(self.env.gateway.sessionRequests.count, 0u);
  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 0u);
  XCTAssertEqual(sender.droppedEventCount, 0);
  QONRemoteConfigV2TelemetryRecord *record = [self.env telemetryRecordForScope:QONRCV2AckScopeA()];
  XCTAssertEqual(record.events.count, 1u);
  XCTAssertEqual(record.events.firstObject.count, 2);
}

- (void)testA429IsRetryable {
  [self.env.gateway scriptTelemetryStatus:429];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertGreaterThan(self.env.scheduler.pendingCount, 0u);
  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.gateway.telemetryRequestCount, 2u);
  XCTAssertEqual(sender.droppedEventCount, 0);
  XCTAssertNil([self.env telemetryRecordForScope:QONRCV2AckScopeA()]);
}

- (void)testNoRequestStatesMoreEventsThanTheContractAllows {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeTelemetrySender];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < QONRemoteConfigV2TelemetryMaximumEntries; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  for (NSUInteger pass = 0; pass < 8; pass++) {
    [sender noteSuccessfulFetch];
    [self.env settle];
  }

  NSUInteger total = 0;
  NSMutableSet<NSString *> *keys = [NSMutableSet new];
  for (NSURLRequest *request in self.env.gateway.telemetryRequests) {
    NSArray *events = QONRCV2TelemetryEvents(request);
    XCTAssertLessThanOrEqual(events.count, QONRemoteConfigV2TelemetryMaximumBatchEntries);
    total += events.count;
    for (NSDictionary *event in events) [keys addObject:event[@"logical_key"]];
  }
  XCTAssertEqual(total, QONRemoteConfigV2TelemetryMaximumEntries);
  XCTAssertEqual(keys.count, QONRemoteConfigV2TelemetryMaximumEntries);
}

@end

#pragma mark - Client telemetry, sender rules

@interface QONRemoteConfigV2TelemetrySenderTests : XCTestCase
@property (nonatomic, strong) QONRCV2TelemetryEnvironment *env;
@end

@implementation QONRemoteConfigV2TelemetrySenderTests

- (void)setUp {
  [super setUp];
  self.env = [QONRCV2TelemetryEnvironment new];
}

- (void)testAFlushIsDueAtTheThresholdAndNotBefore {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:10];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 9; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 0u);

  [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:@"key-9"
       releaseNumber:QONRCV2TelemetryRelease4];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 1u);
  XCTAssertEqual(self.env.transport.lastBatch.events.count, 10u);
}

- (void)testTheTickFlushesABufferBelowTheThreshold {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 0u);
  XCTAssertGreaterThan(self.env.scheduler.pendingCount, 0u);

  [self.env.scheduler runAll];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 1u);
}

- (void)testTheCoalescingMapIsBounded {
  // Threshold above the bound, so nothing flushes and the map is the thing under test.
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 200; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [self.env settle];

  XCTAssertEqual(sender.droppedEventCount, 200 - 64);
  XCTAssertEqual([self.env recordForScope:QONRCV2AckScopeA()].events.count, 64u);
}

- (void)testAnEntryIsKeyedByKindAndKeyOnly {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 4, 2);
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyBeta, 4, 1);
  [sender recordKind:QONRemoteConfigV2TelemetryKindPreloadCorrupt logicalKey:nil releaseNumber:0];
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.transport.batchCount, 1u);
  NSArray<QONRemoteConfigV2TelemetryEvent *> *events = self.env.transport.lastBatch.events;
  XCTAssertEqual(events.count, 3u);
  XCTAssertEqual(events.firstObject.count, 2);
}

/**
 A release rolling over between two flushes must not split one key in two.

 The gateway refuses a whole batch that names the same (kind, logical_key)
 twice, so the release number is an attribute of the entry rather than part of
 its identity: the counts add and the newer release wins.
 */
- (void)testAReleaseRolloverKeepsOneEntry {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 4, 2);
  // The app fetched and activated release 5, and the same key still fails.
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 5, 3);
  // And a read that started before the activation lands afterwards.
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, 4, 1);
  [sender noteSuccessfulFetch];
  [self.env settle];

  NSArray<QONRemoteConfigV2TelemetryEvent *> *events = self.env.transport.lastBatch.events;
  XCTAssertEqual(events.count, 1u);
  XCTAssertEqual(events.firstObject.count, 6);
  // The newest release number, whatever order the observations arrived in.
  XCTAssertEqual(events.firstObject.releaseNumber, 5);
}

- (void)testACountSaturatesAtTheContractCap {
  QONRemoteConfigV2TelemetryStore *store =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:self.env.storage];
  QONRemoteConfigV2TelemetryEvent *saturated = [[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:QONRCV2TelemetryRelease4
               count:QONRemoteConfigV2TelemetryMaximumEventCount
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds];
  QONRemoteConfigV2TelemetryRecord *record =
      [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:@[saturated]];
  XCTAssertTrue([store storeRecord:record forScope:QONRCV2AckScopeA()]);

  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.transport.lastBatch.events.firstObject.count,
                 QONRemoteConfigV2TelemetryMaximumEventCount);
  XCTAssertEqual(sender.droppedEventCount, 3);
}

- (void)testAStaleEventIsPrunedInsteadOfPoisoningItsBatch {
  QONRemoteConfigV2TelemetryStore *store =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:self.env.storage];
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
  QONRemoteConfigV2TelemetryRecord *record =
      [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:@[ancient, fromTheFuture]];
  XCTAssertTrue([store storeRecord:record forScope:QONRCV2AckScopeA()]);

  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:1000];
  [sender bindScope:QONRCV2AckScopeA()];
  // A fresh observation of a third key, shipped in the very same batch.
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyBeta, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.transport.batchCount, 1u);
  NSArray<QONRemoteConfigV2TelemetryEvent *> *events = self.env.transport.lastBatch.events;
  XCTAssertEqual(events.count, 1u);
  XCTAssertEqualObjects(events.firstObject.logicalKey, QONRCV2TelemetryKeyBeta);
  XCTAssertEqual(sender.droppedEventCount, 11);
}

- (void)testAnUnusableClockNeverBuildsABatch {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  self.env.clock.now = 0;
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 2);
  [sender noteSuccessfulFetch];
  [self.env settle];

  // A batch stamped with the epoch floor would be refused whole, so none is built.
  XCTAssertEqual(self.env.transport.batchCount, 0u);
  XCTAssertEqual(sender.droppedEventCount, 0);

  self.env.clock.now = QONRCV2TelemetryObservedAtSeconds * 1000;
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyBeta, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 1u);
}

- (void)testARefundedBatchIsNeverDroppedForWantOfMapRoom {
  [self.env.transport scriptResponse:QONRemoteConfigV2TelemetryResponseNotAddressable times:1];
  // Threshold 10, bound 10: the map fills up again while the batch is out.
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:10
                                                                    flushThreshold:10];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 10; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"batched-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 1u);

  // A refund may never be charged to the bound that stops NEW events.
  XCTAssertEqual([self.env recordForScope:QONRCV2AckScopeA()].events.count, 10u);
  XCTAssertEqual(sender.droppedEventCount, 0);
}

- (void)testAFullBufferSplitsAtTheBatchCap {
  // The threshold is raised to the bound so the whole buffer flushes at once:
  // the split is then the batch cap doing its job, not the threshold.
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSenderWithMaximumEntries:64
                                                                    flushThreshold:64];
  [sender bindScope:QONRCV2AckScopeA()];
  for (NSUInteger index = 0; index < 64; index++) {
    [sender recordKind:QONRemoteConfigV2TelemetryKindDecodeFailure
            logicalKey:[NSString stringWithFormat:@"key-%lu", (unsigned long)index]
         releaseNumber:QONRCV2TelemetryRelease4];
  }
  [self.env settle];

  XCTAssertEqual(self.env.transport.batchCount, 1u);
  XCTAssertEqual(self.env.transport.lastBatch.events.count,
                 QONRemoteConfigV2TelemetryMaximumBatchEntries);

  [sender noteSuccessfulFetch];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 2u);
  XCTAssertEqual(self.env.transport.lastBatch.events.count,
                 64 - QONRemoteConfigV2TelemetryMaximumBatchEntries);
  XCTAssertEqual(self.env.transport.allEvents.count, 64u);
}

- (void)testARetryableFlushIsRetriedAndThenDropped {
  [self.env.transport scriptResponse:QONRemoteConfigV2TelemetryResponseRetryable times:8];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [self.env settle];
  for (NSInteger attempt = 1; attempt < QONRemoteConfigV2TelemetryMaximumAttempts; attempt++) {
    XCTAssertGreaterThan(self.env.scheduler.pendingCount, 0u);
    [self.env.scheduler runAll];
    [self.env settle];
  }

  XCTAssertEqual(self.env.transport.batchCount,
                 (NSUInteger)QONRemoteConfigV2TelemetryMaximumAttempts);
  XCTAssertEqual(sender.droppedEventCount, 3);
  XCTAssertNil([self.env recordForScope:QONRCV2AckScopeA()]);
}

- (void)testAnUnaddressableFlushCostsNoRetryBudget {
  [self.env.transport scriptResponse:QONRemoteConfigV2TelemetryResponseNotAddressable times:1];
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 3);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(sender.droppedEventCount, 0);
  QONRemoteConfigV2TelemetryRecord *record = [self.env recordForScope:QONRCV2AckScopeA()];
  XCTAssertEqual(record.events.count, 1u);
  XCTAssertEqual(record.events.firstObject.count, 3);

  [sender noteSuccessfulFetch];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 2u);
  XCTAssertEqual(self.env.transport.lastBatch.events.firstObject.count, 3);
}

- (void)testObservationsWithoutABoundIdentityAreDropped {
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSender];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 5);
  [sender noteSuccessfulFetch];
  [self.env settle];

  XCTAssertEqual(self.env.transport.batchCount, 0u);
  XCTAssertNil([self.env recordForScope:QONRCV2AckScopeA()]);
}

- (void)testABindDoesNotReSendABatchUnderWay {
  self.env.transport.hang = YES;
  QONRemoteConfigV2TelemetrySender *sender = [self.env makeSender];
  [sender bindScope:QONRCV2AckScopeA()];
  QONRCV2RecordDecodeFailures(sender, QONRCV2TelemetryKeyAlpha, QONRCV2TelemetryRelease4, 1);
  [sender noteSuccessfulFetch];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 1u);

  // An identify that does not actually change the identity.
  [sender bindScope:QONRCV2AckScopeA()];
  [sender noteSuccessfulFetch];
  [self.env settle];
  XCTAssertEqual(self.env.transport.batchCount, 1u);
}

- (void)testTheDurableBufferRoundTrips {
  QONRemoteConfigV2TelemetryStore *store =
      [[QONRemoteConfigV2TelemetryStore alloc] initWithLocalStorage:self.env.storage];
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
  XCTAssertNotNil(decode);
  XCTAssertNotNil(keyless);
  QONRemoteConfigV2TelemetryRecord *record =
      [[QONRemoteConfigV2TelemetryRecord alloc] initWithEvents:@[decode, keyless]];
  XCTAssertTrue([store storeRecord:record forScope:QONRCV2AckScopeA()]);

  QONRemoteConfigV2TelemetryRecord *loaded = [store recordForScope:QONRCV2AckScopeA()];
  XCTAssertEqual(loaded.events.count, 2u);
  XCTAssertEqualObjects(loaded.events.firstObject, decode);
  XCTAssertEqualObjects(loaded.events.lastObject, keyless);
  XCTAssertNil([store recordForScope:QONRCV2AckScopeB()]);
  // No storage key may carry the identity it belongs to.
  XCTAssertFalse([[QONRemoteConfigV2TelemetryStore storageKeyForScope:QONRCV2AckScopeA()]
                     containsString:@"anon-uid-a"]);

  // A record whose bytes disagree with the schema is untrusted whole.
  self.env.storage
      .objects[[QONRemoteConfigV2TelemetryStore storageKeyForScope:QONRCV2AckScopeA()]] =
      @{@"schema_version": @1, @"events": @[@{@"kind": @"not_a_kind"}]};
  XCTAssertNil([store recordForScope:QONRCV2AckScopeA()]);
}

- (void)testAnEventRefusesEveryShapeTheContractForbids {
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:nil
       releaseNumber:1
               count:1
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds]);
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:QONRCV2TelemetryKeyAlpha
       releaseNumber:1
               count:1
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds]);
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:nil
       releaseNumber:-1
               count:1
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds]);
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:nil
       releaseNumber:1
               count:0
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds]);
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:nil
       releaseNumber:1
               count:QONRemoteConfigV2TelemetryMaximumEventCount + 1
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds]);
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindReadBeforeActivate
          logicalKey:nil
       releaseNumber:1
               count:1
lastOccurredAtSeconds:0]);
  NSString *tooLong = [@"" stringByPaddingToLength:QONRemoteConfigV2TelemetryMaximumLogicalKeyBytes + 1
                                        withString:@"k"
                                   startingAtIndex:0];
  XCTAssertNil([[QONRemoteConfigV2TelemetryEvent alloc]
        initWithKind:QONRemoteConfigV2TelemetryKindDecodeFailure
          logicalKey:tooLong
       releaseNumber:1
               count:1
lastOccurredAtSeconds:QONRCV2TelemetryObservedAtSeconds]);
}

@end
