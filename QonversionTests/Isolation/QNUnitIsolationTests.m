#import <XCTest/XCTest.h>
#import "QNUnitIsolationTransport.h"
#import "QNAPIClient.h"
#import "QONRedemptionManager.h"
#import "QNStoreKitService.h"
#import "Qonversion.h"
#import "QNAttributionManager.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#if !QN_UNIT_TEST_ISOLATION
#error QonversionTests requires the UnitIsolation SDK configuration.
#endif

@interface QNUnitIsolationTransportTests : XCTestCase @end
@implementation QNUnitIsolationTransportTests
- (void)testModeAndHostIdentity {
  XCTAssertEqual(QNUnitIsolationTransportVersion, 1);
  XCTAssertEqualObjects(NSBundle.mainBundle.bundleIdentifier, @"io.qonversion.unit-test-host");
  XCTAssertNil(NSClassFromString(@"Sample.AppState"));
  XCTAssertEqual([QNUnitIsolationTransport aggregateCounts][@"outside_case"].unsignedIntegerValue, 0);
  XCTAssertEqual([QNUnitIsolationTransport aggregateCounts][@"store_observers"].unsignedIntegerValue, 0);
}
- (void)testUnmatchedRequestIsDenied {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:1 platformDenials:0];
  XCTestExpectation *done = [self expectationWithDescription:@"local denial"];
  NSURLSession *session = QNUnitIsolationTransport.sharedSession;
  [[session dataTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:9/unmatched"] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    XCTAssertEqualObjects(error.domain, QNUnitIsolationErrorDomain);
    XCTAssertNil(response);
    [done fulfill];
  }] resume];
  [self waitForExpectationsWithTimeout:2 handler:nil];
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testNativeLoopbackControlThenGuardedRequestCannotConnect {
  // Positive control proves this numeric IPv4 listener is reachable. Only the
  // synthetic control uses a socket; the SDK session must not reach the listener.
  int listener = socket(AF_INET, SOCK_STREAM, 0);
  if (listener < 0) { XCTFail(@"Loopback listener creation failed"); return; }
  struct sockaddr_in address = {0};
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 2) != 0) {
    close(listener); XCTFail(@"Loopback listener setup failed"); return;
  }
  socklen_t length = sizeof(address);
  if (getsockname(listener, (struct sockaddr *)&address, &length) != 0) {
    close(listener); XCTFail(@"Loopback address discovery failed"); return;
  }
  int control = socket(AF_INET, SOCK_STREAM, 0);
  if (control < 0 || fcntl(control, F_SETFL, O_NONBLOCK) != 0) {
    if (control >= 0) close(control);
    close(listener); XCTFail(@"Loopback positive control failed"); return;
  }
  int connected = connect(control, (struct sockaddr *)&address, length);
  struct pollfd writable = {.fd = control, .events = POLLOUT};
  int connectError = 0; socklen_t errorLength = sizeof(connectError);
  if ((connected != 0 && errno != EINPROGRESS)
      || poll(&writable, 1, 1000) != 1
      || getsockopt(control, SOL_SOCKET, SO_ERROR, &connectError, &errorLength) != 0 || connectError != 0) {
    close(control); close(listener); XCTFail(@"Loopback positive control connect failed"); return;
  }
  struct pollfd readable = {.fd = listener, .events = POLLIN};
  if (poll(&readable, 1, 1000) != 1 || !(readable.revents & POLLIN)) {
    close(control); close(listener); XCTFail(@"Loopback positive control not observed"); return;
  }
  int accepted = accept(listener, NULL, NULL);
  close(control);
  if (accepted < 0) { close(listener); XCTFail(@"Loopback positive control accept failed"); return; }
  close(accepted);
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:1 platformDenials:0];
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/guarded", ntohs(address.sin_port)]];
  XCTestExpectation *done = [self expectationWithDescription:@"guard denies before connect"];
  [[QNUnitIsolationTransport.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    XCTAssertEqualObjects(error.domain, QNUnitIsolationErrorDomain);
    XCTAssertNil(response);
    [done fulfill];
  }] resume];
  [self waitForExpectationsWithTimeout:2 handler:nil];
  readable.revents = 0;
  XCTAssertEqual(poll(&readable, 1, 250), 0, @"Guarded request reached the loopback listener");
  close(listener);
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testBoundedFixtureThenExhaustion {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:1 platformDenials:0];
  NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9/fixture"];
  [QNUnitIsolationTransport enqueueMethod:@"GET" URL:url status:200 data:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] error:nil];
  for (NSUInteger index = 0; index < 2; index++) {
    XCTestExpectation *done = [self expectationWithDescription:@"bounded fixture"];
    [[QNUnitIsolationTransport.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      if (index == 0) { XCTAssertNil(error); XCTAssertEqual(((NSHTTPURLResponse *)response).statusCode, 200); }
      else XCTAssertEqualObjects(error.domain, QNUnitIsolationErrorDomain);
      [done fulfill];
    }] resume];
    [self waitForExpectationsWithTimeout:2 handler:nil];
  }
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testBackgroundConfigurationRejectedBeforeSessionCreation {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:1];
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"unit.synthetic"];
  XCTAssertThrowsSpecificNamed([QNUnitIsolationTransport sessionWithConfiguration:configuration delegate:nil queue:nil], NSException, @"QNUnitIsolationDenied");
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testLateCallbackCannotConsumeNextCaseFixture {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:0];
  NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9/late-case-a"];
  XCTestExpectation *late = [self expectationWithDescription:@"late case A is denied"];
  // Create a callback in case A but run it only after A is finished and B rejected.
  dispatch_block_t callbackFromA = ^{
    [[QNUnitIsolationTransport.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      XCTAssertEqualObjects(error.domain, QNUnitIsolationErrorDomain);
      XCTAssertNil(response);
      [late fulfill];
    }] resume];
  };
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
  XCTAssertThrowsSpecificNamed([QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:0], NSException, @"QNUnitIsolationLifecycle");
  XCTAssertThrowsSpecificNamed([QNUnitIsolationTransport enqueueMethod:@"GET" URL:url status:200 data:NSData.data error:nil], NSException, @"QNUnitIsolationFixture");
  callbackFromA();
  [self waitForExpectationsWithTimeout:2 handler:nil];
  XCTAssertEqual([QNUnitIsolationTransport aggregateCounts][@"outside_case"].unsignedIntegerValue, 1);
  XCTAssertEqual([QNUnitIsolationTransport aggregateCounts][@"captured"].unsignedIntegerValue, 0);
}
- (void)testConfigurationOverrideCannotReplaceMandatoryProtocol {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:0];
  NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  configuration.protocolClasses = @[];
  NSURLSession *session = [QNUnitIsolationTransport sessionWithConfiguration:configuration delegate:nil queue:nil];
  XCTAssertEqual(session.configuration.protocolClasses.count, 1);
  XCTAssertEqualObjects(NSStringFromClass(session.configuration.protocolClasses.firstObject), @"QNUnitIsolationURLProtocol");
  configuration.protocolClasses = @[];
  XCTAssertEqual(session.configuration.protocolClasses.count, 1);
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testInjectedNativeSessionRejectedBeforeUse {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:2];
  NSURLSession *unguarded = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
  QNAPIClient *client = [QNAPIClient new];
  QONRedemptionManager *redemption = [QONRedemptionManager new];
  XCTAssertThrowsSpecificNamed(client.session = unguarded, NSException, @"QNUnitIsolationDenied");
  XCTAssertThrowsSpecificNamed(redemption.session = unguarded, NSException, @"QNUnitIsolationDenied");
  [unguarded invalidateAndCancel];
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
@end

@interface QNUnitIsolationSDKStartupTests : XCTestCase @end
@implementation QNUnitIsolationSDKStartupTests
- (void)testSecondarySDKInitializationUsesFakeStoreAndDeniedTransport {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:1 platformDenials:0];
  NSString *suite = @"io.qonversion.unit.synthetic.startup";
  [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:suite];
  QONConfiguration *configuration = [[QONConfiguration alloc] initWithProjectKey:@"synthetic-unit-key" launchMode:QONLaunchModeAnalytics];
  [configuration setCustomUserDefaultsSuitename:suite];
  [configuration setProxyURL:@"http://127.0.0.1:9/"];
  Qonversion *sdk = [Qonversion initWithConfig:configuration];
  XCTAssertNotNil(sdk);
  NSPredicate *seen = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
    return [QNUnitIsolationTransport aggregateCounts][@"denied"].unsignedIntegerValue >= 1;
  }];
  XCTestExpectation *attempted = [self expectationForPredicate:seen evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[attempted] timeout:3];
  XCTAssertGreaterThan([QNUnitIsolationTransport aggregateCounts][@"store_observers"].unsignedIntegerValue, 0);
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
  [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:suite];
  // No second case is permitted: SDK singleton callbacks can outlive this method.
}
@end

@interface QNUnitIsolationPlatformTests : XCTestCase @end
@implementation QNUnitIsolationPlatformTests
- (void)testAttributionDeniedBeforeDelayedPlatformTask {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:1];
  QNAttributionManager *manager = [QNAttributionManager new];
  XCTAssertThrowsSpecificNamed([manager addAppleSearchAttributionData], NSException, @"QNUnitIsolationDenied");
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testStoreObserverIsInMemoryAndRestoreDenied {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:1];
  NSUInteger before = [QNUnitIsolationTransport aggregateCounts][@"store_observers"].unsignedIntegerValue;
  QNStoreKitService *service = [QNStoreKitService new];
  XCTAssertEqual([QNUnitIsolationTransport aggregateCounts][@"store_observers"].unsignedIntegerValue, before + 1);
  XCTAssertThrowsSpecificNamed([service restore], NSException, @"QNUnitIsolationDenied");
  XCTAssertEqualObjects(QNUnitIsolationTransport.storefrontCountryCode, @"ZZZ");
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
- (void)testProductRequestDeniedBeforeStoreRequestStart {
  [QNUnitIsolationTransport beginCaseWithExpectedDenials:0 platformDenials:1];
  QNStoreKitService *service = [QNStoreKitService new];
  XCTAssertThrowsSpecificNamed([service loadProducts:[NSSet setWithObject:@"synthetic.product"]], NSException, @"QNUnitIsolationDenied");
  XCTAssertTrue([QNUnitIsolationTransport finishCase]);
}
@end
