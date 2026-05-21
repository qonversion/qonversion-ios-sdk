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
#import "QNTestConstants.h"

#pragma mark - URLProtocol stub

@interface QONRedemptionURLProtocolStub : NSURLProtocol
@end

static NSInteger gStubStatusCode = 200;
static NSData *gStubBody = nil;
static NSError *gStubError = nil;
static NSMutableArray<NSURL *> *gStubURLs = nil;
static NSMutableArray<NSDictionary *> *gStubBodies = nil;

// Per-URL queue: maps endpoint path -> NSArray of dicts
//   { @"status": NSNumber, @"body": NSData, @"error": NSError (optional) }
static NSMutableDictionary<NSString *, NSMutableArray *> *gStubQueueByPath = nil;

@implementation QONRedemptionURLProtocolStub

+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b { return NO; }

- (void)startLoading {
  NSURL *url = self.request.URL;
  if (gStubURLs) {
    [gStubURLs addObject:url];
  }
  if (gStubBodies && self.request.HTTPBody) {
    id parsed = [NSJSONSerialization JSONObjectWithData:self.request.HTTPBody options:0 error:nil];
    if ([parsed isKindOfClass:[NSDictionary class]]) {
      [gStubBodies addObject:parsed];
    }
  }

  // Per-path queue takes precedence (multi-step flows like 409 → status).
  NSString *path = url.path ?: @"";
  NSDictionary *response = nil;
  if (gStubQueueByPath) {
    for (NSString *key in gStubQueueByPath.allKeys) {
      if ([path hasSuffix:key]) {
        NSMutableArray *queue = gStubQueueByPath[key];
        if (queue.count > 0) {
          response = queue.firstObject;
          [queue removeObjectAtIndex:0];
        }
        break;
      }
    }
  }

  NSInteger status = gStubStatusCode;
  NSData *body = gStubBody;
  NSError *error = gStubError;
  if (response) {
    status = [response[@"status"] integerValue];
    body = response[@"body"];
    error = response[@"error"];
  }

  if (error) {
    [self.client URLProtocol:self didFailWithError:error];
    return;
  }

  NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:url
                                                                statusCode:status
                                                               HTTPVersion:@"HTTP/1.1"
                                                              headerFields:@{@"Content-Type": @"application/json"}];
  [self.client URLProtocol:self didReceiveResponse:httpResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
  if (body) {
    [self.client URLProtocol:self didLoadData:body];
  }
  [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

#pragma mark - Tests

@interface QONRedemptionManagerTests : XCTestCase
@property (nonatomic, strong) QONRedemptionManager *manager;
@property (nonatomic, strong) id mockProductCenterManager;
@property (nonatomic, strong) id mockUserInfoService;
@end

@implementation QONRedemptionManagerTests

- (void)setUp {
  [super setUp];

  // Reset stub state
  gStubStatusCode = 200;
  gStubBody = nil;
  gStubError = nil;
  gStubURLs = [NSMutableArray new];
  gStubBodies = [NSMutableArray new];
  gStubQueueByPath = [NSMutableDictionary new];

  NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  config.protocolClasses = @[[QONRedemptionURLProtocolStub class]];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

  _manager = [QONRedemptionManager new];
  _manager.session = session;
  _manager.baseURL = @"https://api2.qonversion.io/";

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
  gStubQueueByPath = nil;
  [super tearDown];
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

#pragma mark - handleRedemptionLink

- (void)testMalformedURLReturnsInvalidToken {
  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/garbage"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
    XCTAssertEqual(result, QONRedemptionResultInvalidToken);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testValidURLParsesTokenAndPostsBody {
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"user_id": @"app_user_42"} options:0 error:nil];

  // Stub identify to return immediately so completion fires.
  OCMStub([_mockProductCenterManager identify:OCMOCK_ANY completion:[OCMArg invokeBlockWithArgs:[NSNull null], [NSNull null], nil]]);

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
    XCTAssertEqual(result, QONRedemptionResultSuccess);
    XCTAssertEqual(gStubURLs.count, (NSUInteger)1);
    XCTAssertTrue([gStubURLs.firstObject.path hasSuffix:kWebRedeemEndpoint]);

    XCTAssertEqual(gStubBodies.count, (NSUInteger)1);
    NSDictionary *body = gStubBodies.firstObject;
    XCTAssertEqualObjects(body[@"token"], @"tok_xyz123");
    XCTAssertEqualObjects(body[@"anon_user_id"], @"QON_anon_test_id");
    XCTAssertEqualObjects(body[@"restore_behavior"], @"transfer");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testSuccessTriggersIdentify {
  // RT5-N2 contract test: identify(newUserId) must be triggered on 2xx
  // redeem response (which in turn triggers a launch/permissions fetch
  // by virtue of QNProductCenterManager.identify: contract).
  gStubStatusCode = 200;
  gStubBody = [NSJSONSerialization dataWithJSONObject:@{@"user_id": @"app_user_42"} options:0 error:nil];

  XCTestExpectation *identifyExp = [self expectationWithDescription:@"identify called"];

  OCMExpect([_mockProductCenterManager identify:@"app_user_42" completion:OCMOCK_ANY])
    .andDo(^(NSInvocation *invocation) {
      __unsafe_unretained void (^block)(id, id) = nil;
      [invocation getArgument:&block atIndex:3];
      if (block) block(nil, nil);
      [identifyExp fulfill];
    });

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *completionExp = [self expectationWithDescription:@"completion called"];

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
    XCTAssertEqual(result, QONRedemptionResultSuccess);
    [completionExp fulfill];
  }];

  [self waitForExpectations:@[identifyExp, completionExp] timeout:5.0];
  OCMVerifyAll(_mockProductCenterManager);
}

- (void)test404ReturnsInvalidToken {
  gStubStatusCode = 404;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
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

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
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

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
    XCTAssertEqual(result, QONRedemptionResultAlreadyConsumed);
    // Two requests: redeem (409) then status (200).
    XCTAssertEqual(gStubURLs.count, (NSUInteger)2);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testNetworkErrorReturnsNetworkError {
  gStubError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];

  NSURL *url = [NSURL URLWithString:@"https://screens.qonversion.io/r/proj_abc/tok_xyz123"];
  XCTestExpectation *exp = [self expectationWithDescription:@""];

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
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

  [_manager handleRedemptionLink:url completion:^(QONRedemptionResult result) {
    XCTAssertEqual(result, QONRedemptionResultInvalidToken);
    // No HTTP request must have been issued for a rejected scheme — this is
    // the load-bearing security assertion. Any leak of the token over the
    // network would already constitute partial compromise.
    XCTAssertEqual(gStubURLs.count, (NSUInteger)0);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

#pragma mark - Reissue

- (void)testReissueWithEmailPosts200 {
  gStubStatusCode = 200;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  XCTestExpectation *exp = [self expectationWithDescription:@""];
  [_manager reissueWithEmail:@"user@example.com" completion:^(BOOL success, NSInteger statusCode, NSError * _Nullable error) {
    XCTAssertTrue(success);
    XCTAssertEqual(statusCode, 200);
    XCTAssertNil(error);
    XCTAssertTrue([gStubURLs.firstObject.path hasSuffix:kWebRedeemReissueEndpoint]);
    XCTAssertEqualObjects(gStubBodies.firstObject[@"email"], @"user@example.com");
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testReissueRateLimited429 {
  gStubStatusCode = 429;
  gStubBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

  XCTestExpectation *exp = [self expectationWithDescription:@""];
  [_manager reissueWithEmail:@"user@example.com" completion:^(BOOL success, NSInteger statusCode, NSError * _Nullable error) {
    XCTAssertFalse(success);
    XCTAssertEqual(statusCode, 429);
    [exp fulfill];
  }];

  [self waitForExpectations:@[exp] timeout:5.0];
}

@end
