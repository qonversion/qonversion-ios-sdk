//
//  QONRedemptionManagerTests.m
//  QonversionTests
//
//  Unit tests for the Web 2 App redemption surface (DEV-847 / M1).
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "QONRedemptionManager.h"
#import "QONRedemptionResult.h"
#import "QNAPIConstants.h"
#import "QNProductCenterManager.h"
#import "QNUserInfoServiceInterface.h"
#import "QONRequestTrigger.h"
#import "QNTestConstants.h"
#import "QNUnitIsolationTransport.h"

#pragma mark - In-memory fixture data

static NSInteger gStubStatusCode = 200;
static NSData *gStubBody = nil;
static NSError *gStubError = nil;
static NSMutableArray<NSURL *> *gStubURLs = nil;
static NSMutableArray<NSDictionary *> *gStubBodies = nil;
static NSMutableArray<NSDictionary *> *gStubHeaders = nil;

// Per-URL queue: maps endpoint path -> NSArray of dicts
//   { @"status": NSNumber, @"body": NSData, @"error": NSError (optional) }
static NSMutableDictionary<NSString *, NSMutableArray *> *gStubQueueByPath = nil;

#pragma mark - Tests

@interface QONRedemptionManagerTests : XCTestCase
@property (nonatomic, strong) QONRedemptionManager *manager;
@property (nonatomic, strong) id mockProductCenterManager;
@property (nonatomic, strong) id mockUserInfoService;
@end

@implementation QONRedemptionManagerTests

- (void)setUp {
  [super setUp];
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:0];

  // Reset stub state
  gStubStatusCode = 200;
  gStubBody = nil;
  gStubError = nil;
  gStubURLs = [NSMutableArray new];
  gStubBodies = [NSMutableArray new];
  gStubHeaders = [NSMutableArray new];
  gStubQueueByPath = [NSMutableDictionary new];

  NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  NSURLSession *session = [QNUnitIsolationTransport sessionWithConfiguration:config delegate:nil queue:nil];

  _manager = [QONRedemptionManager new];
  _manager.session = session;
  _manager.baseURL = @"https://unit.example.invalid/";

  _mockProductCenterManager = OCMClassMock([QNProductCenterManager class]);
  _mockUserInfoService = OCMProtocolMock(@protocol(QNUserInfoServiceInterface));
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"QON_anon_test_id");

  _manager.productCenterManager = _mockProductCenterManager;
  _manager.userInfoService = _mockUserInfoService;
}

- (void)tearDown {
  [_mockProductCenterManager stopMocking];
  [_mockUserInfoService stopMocking];
  _manager = nil;
  gStubURLs = nil;
  gStubBodies = nil;
  gStubHeaders = nil;
  gStubQueueByPath = nil;
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
  [super tearDown];
}


- (void)prepareFixtureResponses {
  for (NSString *endpoint in @[kWebRedeemEndpoint, kWebRedeemStatusEndpoint, kWebRedeemReissueEndpoint]) {
    NSArray *responses = gStubQueueByPath[endpoint];
    if (!responses) {
      NSMutableDictionary *response = [@{@"status": @(gStubStatusCode), @"body": gStubBody ?: [NSData data]} mutableCopy];
      if (gStubError) response[@"error"] = gStubError;
      responses = @[response];
    }
    NSURL *url = [NSURL URLWithString:[self.manager.baseURL stringByAppendingString:endpoint]];
    for (NSDictionary *response in responses) {
      [QNUnitIsolationTransport enqueueMethod:@"POST" URL:url status:[response[@"status"] integerValue]
        data:response[@"body"] ?: [NSData data] error:response[@"error"]];
    }
  }
}
- (void)captureFixtureRequests {
  [gStubURLs removeAllObjects]; [gStubBodies removeAllObjects]; [gStubHeaders removeAllObjects];
  for (NSURLRequest *request in [QNUnitIsolationTransport capturedRequests]) {
    [gStubURLs addObject:request.URL];
    if (request.HTTPBody) {
      id body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
      if ([body isKindOfClass:NSDictionary.class]) [gStubBodies addObject:body];
    }
    [gStubHeaders addObject:request.allHTTPHeaderFields ?: @{}];
  }
}

#pragma mark - URL parsing

- (void)testTokenFromURLValidUniversalLink {
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTAssertEqualObjects([QONRedemptionManager tokenFromURL:url], @"tok_xyz123");
}

- (void)testTokenFromURLAcceptsCustomScheme_HostAppForwardingOnly {
  // host-app→SDK internal forwarding fallback. `tokenFromURL` is a pure
  // parser used by the (private) internal forwarding path; the email-borne
  // entry point `handleRedemptionLink:completion:` is responsible for
  // gating the transport scheme to https (Universal Links only) per
  // spec rule RT2-W3.
  NSURL *url = [NSURL URLWithString:@"qonversion://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTAssertEqualObjects([QONRedemptionManager tokenFromURL:url], @"tok_xyz123");
}

- (void)testTokenFromURLStripsQueryString {
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123?utm=email"];
  XCTAssertEqualObjects([QONRedemptionManager tokenFromURL:url], @"tok_xyz123");
}

- (void)testTokenFromURLMissingTokenReturnsNil {
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/"];
  XCTAssertNil([QONRedemptionManager tokenFromURL:url]);
}

- (void)testTokenFromURLMissingRPrefixReturnsNil {
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/proj_abc/tok_xyz123"];
  XCTAssertNil([QONRedemptionManager tokenFromURL:url]);
}

- (void)testTokenFromURLNilReturnsNil {
  XCTAssertNil([QONRedemptionManager tokenFromURL:nil]);
}

- (void)testTokenFromURL_RSegmentMustBeFirst_NoTypeConfusion {
  // #8 — the "r" redemption prefix must be the FIRST path segment. A nested
  // "r" segment (e.g. /foo/r/proj/token) must NOT be mistaken for the
  // redemption prefix; the canonical structure is /r/{project_uid}/{token}.
  // (Android parity; defends against path type-confusion.)
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/foo/r/proj_abc/tok_xyz123"];
  XCTAssertNil([QONRedemptionManager tokenFromURL:url]);
}

#pragma mark - handleRedemptionLink

- (void)testMalformedURLReturnsInvalidToken {
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/garbage"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultInvalidToken);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testValidURLParsesTokenAndPostsBody {
  // CANONICAL CONTRACT (Web2App M1.5): request body is
  //   { "token": <token>, "app_uid": <obtainUserID>, "restore_behavior": <behavior> }
  // The SDK previously sent "anon_user_id"; the field was renamed to
  // "app_uid" (value unchanged = obtainUserID). api-gateway / purchaseman
  // read "app_uid".
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"QON_anon_test_id"} options:0 error:nil];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultSuccess);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)1);
    XCTAssertTrue([gStubURLs.firstObject.path hasSuffix:kWebRedeemEndpoint]);

    XCTAssertEqual(gStubBodies.count, (NSUInteger)1);
    NSDictionary *body = gStubBodies.firstObject;
    XCTAssertEqualObjects(body[@"token"], @"tok_xyz123");
    XCTAssertEqualObjects(body[@"app_uid"], @"QON_anon_test_id");
    XCTAssertNil(body[@"anon_user_id"], @"legacy field must NOT be sent");
    XCTAssertEqualObjects(body[@"restore_behavior"], @"transfer");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testSuccessTriggersRefreshNotIdentify {
  // CANONICAL CONTRACT (Web2App M1.5): under grant-first entitlement the
  // server has ALREADY granted the entitlement and the response is
  //   { "redeemed": bool, "app_uid": string }   (NO user_id).
  // On success the SDK MUST NOT call identify(userId)/merge. Instead it
  // triggers a server-state refresh (launch / checkEntitlements) for the
  // current user so the next checkEntitlements sees the granted product.
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"QON_anon_test_id"} options:0 error:nil];

  XCTestExpectation *refreshExp = [self expectationWithDescription:@"launch/refresh triggered"];

  // identify: must NEVER be called on the redeem-success path.
  OCMReject([_mockProductCenterManager identify:OCMOCK_ANY completion:OCMOCK_ANY]);

  OCMExpect([_mockProductCenterManager launchWithTrigger:QONRequestTriggerActualizePermissions completion:OCMOCK_ANY])
    .andDo(^(NSInvocation *invocation) {
      [refreshExp fulfill];
    });

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *completionExp = [self expectationWithDescription:@"completion called"];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultSuccess);
    [completionExp fulfill];
  }];

  [self waitForExpectations:@[refreshExp, completionExp] timeout:5.0];
  OCMVerifyAll(_mockProductCenterManager);
}

- (void)test404ReturnsInvalidToken {
  gStubStatusCode = 404;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultInvalidToken);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test410ReturnsTokenExpired {
  gStubStatusCode = 410;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultTokenExpired);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test409WithStatusConsumedReturnsAlreadyConsumed {
  // First call: /v4/web/redeem returns 409.
  // Second call: /v4/web/redeem/status returns 200 + {consumed: true}.
  NSData *statusBody = [NSJSONSerialization dataWithJSONObject:@{@"consumed": @YES} options:0 error:nil];

  gStubQueueByPath[kWebRedeemStatusEndpoint] = [@[
    @{@"status": @200, @"body": statusBody}
  ] mutableCopy];
  gStubQueueByPath[kWebRedeemEndpoint] = [@[
    @{@"status": @409, @"body": [@"{}" dataUsingEncoding:NSUTF8StringEncoding]}
  ] mutableCopy];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultAlreadyConsumed);
    // Two requests: redeem (409) then status (200).
    XCTAssertEqual(gStubURLs.count, (NSUInteger)2);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test409WithStatusExpiredReturnsTokenExpired {
  // #5 — 409 recovery: /v4/web/redeem/status reports the token is NOT consumed
  // but IS expired. The SDK must honour the `expired` flag and surface
  // QONRedemptionResultTokenExpired (Android parity) so the host offers the
  // reissue flow — NOT QONRedemptionResultInvalidToken.
  NSData *statusBody = [NSJSONSerialization dataWithJSONObject:@{@"consumed": @NO, @"expired": @YES} options:0 error:nil];
  gStubQueueByPath[kWebRedeemStatusEndpoint] = [@[ @{@"status": @200, @"body": statusBody} ] mutableCopy];
  gStubQueueByPath[kWebRedeemEndpoint] = [@[ @{@"status": @409, @"body": [@"{}" dataUsingEncoding:NSUTF8StringEncoding]} ] mutableCopy];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultTokenExpired);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test409WithStatusConsumedAndExpiredPrefersAlreadyConsumed {
  // #5 — when the status reports BOTH consumed and expired, "consumed" is the
  // stronger statement (the token was actually used), so AlreadyConsumed wins.
  NSData *statusBody = [NSJSONSerialization dataWithJSONObject:@{@"consumed": @YES, @"expired": @YES} options:0 error:nil];
  gStubQueueByPath[kWebRedeemStatusEndpoint] = [@[ @{@"status": @200, @"body": statusBody} ] mutableCopy];
  gStubQueueByPath[kWebRedeemEndpoint] = [@[ @{@"status": @409, @"body": [@"{}" dataUsingEncoding:NSUTF8StringEncoding]} ] mutableCopy];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultAlreadyConsumed);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testNetworkErrorReturnsNetworkError {
  gStubError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultNetworkError);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testHandleRedemptionLink_RejectsCustomScheme_EmailContext {
  // Spec rule RT2-W3: Universal Links (https) are the ONLY supported email
  // transport. Any non-https scheme (notably `qonversion://`) can be claimed
  // by any installed app's CFBundleURLTypes and used to hijack the token, so
  // the email-borne entry point MUST reject it without ever hitting the
  // network. The structural parser (`+tokenFromURL:`) remains scheme-
  // agnostic; gating is the responsibility of `handleRedemptionLink:`.
  NSURL *url = [NSURL URLWithString:@"qonversion://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultInvalidToken);
    // No HTTP request must have been issued for a rejected scheme — this is
    // the load-bearing security assertion. Any leak of the token over the
    // network would already constitute partial compromise.
    XCTAssertEqual(gStubURLs.count, (NSUInteger)0);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testHandleRedemptionLink_RejectsForeignHost {
  // #8 — host pinning: the redemption link host MUST be screens.qonversion.io.
  // A foreign host (even over https with a structurally valid /r/ path) must be
  // rejected WITHOUT issuing any network request, so a single-use token can
  // never be leaked off-host. (Android parity; defense-in-depth.)
  NSURL *url = [NSURL URLWithString:@"https://evil.example.com/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultInvalidToken);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)0, @"no request may be issued for a foreign host");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testHandleRedemptionLink_PinnedHostIsCaseInsensitive {
  // #8 — host comparison is case-insensitive (DNS hosts are case-insensitive),
  // so a mixed-case but legitimate host still redeems.
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"QON_anon_test_id"} options:0 error:nil];

  NSURL *url = [NSURL URLWithString:@"https://Screens.Qonversion.IO/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultSuccess);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)1);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

#pragma mark - Idempotency-Key (overview r6)

static BOOL QONIsValidUUID(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return NO;
  }
  return [[NSUUID alloc] initWithUUIDString:value] != nil;
}

- (void)testRedeemRequestCarriesValidIdempotencyKeyHeader {
  // overview r6: the redeem request MUST carry a mandatory `Idempotency-Key`
  // (a SDK-generated UUIDv4) so the backend can dedup double-taps / retries.
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"QON_anon_test_id"} options:0 error:nil];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(gStubHeaders.count, (NSUInteger)1);
    NSString *key = gStubHeaders.firstObject[@"Idempotency-Key"];
    XCTAssertNotNil(key, @"redeem request must carry an Idempotency-Key header");
    XCTAssertTrue(QONIsValidUUID(key), @"Idempotency-Key must be a valid UUID, got %@", key);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testIdempotencyKeyIsStableAcrossHTTPRetryOfSameLogicalRedeem {
  // The key is per *logical* redeem call, NOT per HTTP attempt. A transient
  // transport failure followed by an SDK-level retry of the same logical
  // redeem must reuse the same Idempotency-Key so the backend dedups it.
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"QON_anon_test_id"} options:0 error:nil];

  // First logical redeem: capture its key. The status-recovery path (409 →
  // /status) is part of the same logical redeem, so both HTTP calls must
  // share one key.
  NSData *statusBody = [NSJSONSerialization dataWithJSONObject:@{@"consumed": @YES} options:0 error:nil];
  gStubQueueByPath[kWebRedeemStatusEndpoint] = [@[ @{@"status": @200, @"body": statusBody} ] mutableCopy];
  gStubQueueByPath[kWebRedeemEndpoint] = [@[ @{@"status": @409, @"body": [@"{}" dataUsingEncoding:NSUTF8StringEncoding]} ] mutableCopy];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(gStubHeaders.count, (NSUInteger)2, @"redeem + status recovery call");
    NSString *redeemKey = gStubHeaders[0][@"Idempotency-Key"];
    NSString *statusKey = gStubHeaders[1][@"Idempotency-Key"];
    XCTAssertTrue(QONIsValidUUID(redeemKey));
    XCTAssertEqualObjects(redeemKey, statusKey, @"same logical redeem must reuse the Idempotency-Key across HTTP calls");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testSeparateLogicalRedeemsGetDistinctIdempotencyKeys {
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"QON_anon_test_id"} options:0 error:nil];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];

  XCTestExpectation *exp1 = [self expectationWithDescription:@"first"];
  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests]; [exp1 fulfill]; }];
  [self waitForExpectations:@[exp1] timeout:5.0];
  NSString *firstKey = gStubHeaders.lastObject[@"Idempotency-Key"];

  XCTestExpectation *exp2 = [self expectationWithDescription:@"second"];
  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests]; [exp2 fulfill]; }];
  [self waitForExpectations:@[exp2] timeout:5.0];
  NSString *secondKey = gStubHeaders.lastObject[@"Idempotency-Key"];

  XCTAssertTrue(QONIsValidUUID(firstKey));
  XCTAssertTrue(QONIsValidUUID(secondKey));
  XCTAssertNotEqualObjects(firstKey, secondKey, @"distinct logical redeems must get distinct keys");
}

#pragma mark - baseURL override

- (void)testRedeemUsesConfiguredBaseURLNotDefault {
  // A client configured with a custom / proxy baseURL must have redemption
  // requests routed there, not to kAPIBase.
  _manager.baseURL = @"https://proxy.example.test/";
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"redeemed": @YES, @"app_uid": @"u"} options:0 error:nil];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(gStubURLs.count, (NSUInteger)1);
    XCTAssertEqualObjects(gStubURLs.firstObject.host, @"proxy.example.test");
    XCTAssertFalse([gStubURLs.firstObject.host isEqualToString:@"api2.qonversion.io"]);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testManagerDefaultsToAPIBaseWhenNotConfigured {
  QONRedemptionManager *fresh = [QONRedemptionManager new];
  XCTAssertEqualObjects(fresh.baseURL, kAPIBase);
}

#pragma mark - Server errors (429 / 5xx) are retryable, not "network"

- (void)test429ReturnsRetryable {
  gStubStatusCode = 429;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultRetryable);
    XCTAssertNotEqual(result, QONRedemptionResultNetworkError, @"rate limit is a live-server response, not 'no network'");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test500ReturnsRetryable {
  gStubStatusCode = 500;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultRetryable);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test503ReturnsRetryable {
  gStubStatusCode = 503;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultRetryable);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)test401ReturnsRetryableNotNetwork {
  // Auth/config server response — a live 401 is not "no network".
  gStubStatusCode = 401;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertNotEqual(result, QONRedemptionResultNetworkError);
    XCTAssertEqual(result, QONRedemptionResultRetryable);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

#pragma mark - Empty app_uid is not silently omitted

- (void)testEmptyAppUIDFailsFastWithoutNetworkRequest {
  // Without an app_uid the backend cannot attach the granted entitlement to
  // a user, so the SDK must NOT silently fire a redeem that omits it. It
  // fails fast (retryable) and issues no network request.
  [_mockUserInfoService stopMocking];
  _mockUserInfoService = OCMProtocolMock(@protocol(QNUserInfoServiceInterface));
  OCMStub([_mockUserInfoService obtainUserID]).andReturn(@"");
  _manager.userInfoService = _mockUserInfoService;

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [self prepareFixtureResponses];
  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) { [self captureFixtureRequests];
    XCTAssertEqual(result, QONRedemptionResultRetryable);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)0, @"no redeem request must be issued without app_uid");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

#pragma mark - Reissue

- (void)testReissueWithEmailPosts200 {
  gStubStatusCode = 200;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  XCTestExpectation *exp = [self expectationWithDescription:@""];
  [self prepareFixtureResponses];
  [_manager reissueWithEmail:@"user@example.com" completion:^(BOOL success, NSInteger statusCode, NSError * _Nullable error) { [self captureFixtureRequests];
    XCTAssertTrue(success);
    XCTAssertEqual(statusCode, 200);
    XCTAssertNil(error);
    XCTAssertTrue([gStubURLs.firstObject.path hasSuffix:kWebRedeemReissueEndpoint]);
    XCTAssertEqualObjects(gStubBodies.firstObject[@"email"], @"user@example.com");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testReissueWithEmptyEmailFailsValidationWithoutNetwork {
  // #10 — an empty email must NOT trigger a useless POST with an empty body.
  // The SDK gates it and returns a validation failure (success NO + error),
  // issuing no network request.
  XCTestExpectation *exp = [self expectationWithDescription:@""];
  [self prepareFixtureResponses];
  [_manager reissueWithEmail:@"" completion:^(BOOL success, NSInteger statusCode, NSError * _Nullable error) { [self captureFixtureRequests];
    XCTAssertFalse(success);
    XCTAssertNotNil(error, @"empty email must yield a validation error");
    XCTAssertEqualObjects(error.domain, QONRedemptionErrorDomain);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)0, @"no reissue POST for empty email");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testReissueWithWhitespaceEmailFailsValidationWithoutNetwork {
  // #10 — a whitespace-only email is also empty after trimming.
  XCTestExpectation *exp = [self expectationWithDescription:@""];
  [self prepareFixtureResponses];
  [_manager reissueWithEmail:@"   \n\t" completion:^(BOOL success, NSInteger statusCode, NSError * _Nullable error) { [self captureFixtureRequests];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)0);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testReissueRateLimited429 {
  gStubStatusCode = 429;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  XCTestExpectation *exp = [self expectationWithDescription:@""];
  [self prepareFixtureResponses];
  [_manager reissueWithEmail:@"user@example.com" completion:^(BOOL success, NSInteger statusCode, NSError * _Nullable error) { [self captureFixtureRequests];
    XCTAssertFalse(success);
    XCTAssertEqual(statusCode, 429);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

@end
