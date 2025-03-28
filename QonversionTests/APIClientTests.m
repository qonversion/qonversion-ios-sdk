#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNTestConstants.h"
#import "QNAPIClient.h"
#import "QNRequestSerializer.h"

#import "Helpers/XCTestCase+TestJSON.h"

NSString *const kTestAPIKey = @"QNAPIClient_test_api_key";

@interface QNAPIClient (Private)
- (NSDictionary *)enrichParameters:(NSDictionary *)parameters;

- (void)dataTaskWithRequest:(NSURLRequest *)request
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion;
@end

@interface APIClientTests : XCTestCase

@property (nonatomic) id mockSession;
@property (nonatomic) id request;
@property (nonatomic) id mockRequestSerializer;

@property (nonatomic) QNAPIClient *client;
@end

@implementation APIClientTests

- (void)setUp {
  [super setUp];
  
  _mockSession = OCMClassMock([NSURLSession class]);
  _mockRequestSerializer = OCMClassMock([QNRequestSerializer class]);
  _request = OCMClassMock([NSURLRequest class]);
  
  _client = [[QNAPIClient alloc] init];
  
  [_client setRequestSerializer:_mockRequestSerializer];
  [_client setSession:_mockSession];
  [_client setApiKey:kTestAPIKey];
  [_client setSDKVersion:@"10.11.12"];
}

- (void)tearDown {
  [super tearDown];
  
  _request = nil;
  _mockSession = nil;
  _client = nil;
  _mockRequestSerializer = nil;
  
  [_mockSession stopMocking];
  [_request stopMocking];
  [_mockRequestSerializer stopMocking];
}

- (void)testThatEnrichingAddWaitingFields {
  NSDictionary *result = [_client enrichParameters:@{}];
  XCTAssertNotNil(result);
  XCTAssertEqual(result.count, 5);
  XCTAssertNotNil(result[@"access_token"]);
  XCTAssertNotNil(result[@"q_uid"]);
  XCTAssertNotNil(result[@"client_uid"]);
  XCTAssertNotNil(result[@"version"]);
}

- (void)testThatClientSendsRequest {
  OCMStub([self.mockRequestSerializer addTryCountToHeader:OCMOCK_ANY request:self.request]).andReturn(self.request);
  [_client dataTaskWithRequest:self.request completion:nil];
  OCMVerify([self.mockSession dataTaskWithRequest:self.request
                                completionHandler:OCMOCK_ANY]);
}

- (void)testThatClientCallsCompletionHandler {
  OCMStub([self.mockRequestSerializer addTryCountToHeader:OCMOCK_ANY request:self.request]).andReturn(self.request);
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  OCMStub([_mockSession dataTaskWithRequest:self.request completionHandler:[OCMArg invokeBlock]]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testThatClientParseNullData {
  OCMStub([self.mockRequestSerializer addTryCountToHeader:OCMOCK_ANY request:self.request]).andReturn(self.request);
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  
  NSError *networkError = [NSError errorWithDomain:NSURLErrorDomain code:404 userInfo:nil];
  
  OCMStub([_mockSession dataTaskWithRequest:self.request
                          completionHandler:([OCMArg invokeBlockWithArgs:[NSNull null], [NSNull null], networkError, nil])]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 404);
    XCTAssertNil(dict);
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testThatClientParseCorrectData {
  OCMStub([self.mockRequestSerializer addTryCountToHeader:OCMOCK_ANY request:self.request]).andReturn(self.request);
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  
  OCMStub([_mockSession dataTaskWithRequest:self.request
                          completionHandler:([OCMArg invokeBlockWithArgs:[self fileDataFromContentsOfFile:keyQNInitFailedJSON], [NSNull null], [NSNull null], nil])]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    XCTAssertNil(dict);
    XCTAssertNotNil(error);
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testThatClientDetectBrokenData {
  OCMStub([self.mockRequestSerializer addTryCountToHeader:OCMOCK_ANY request:self.request]).andReturn(self.request);
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  NSData *brokenJson = [self fileDataFromContentsOfFile:keyQNBrokenJSON];
  
  OCMStub([_mockSession dataTaskWithRequest:self.request
                          completionHandler:([OCMArg invokeBlockWithArgs:brokenJson, [NSNull null], [NSNull null], nil])]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    XCTAssertNil(dict);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 17);
    XCTAssertEqualObjects(error.domain, keyQONErrorDomain);
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

@end
