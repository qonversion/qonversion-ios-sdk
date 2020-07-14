#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNAPIClient.h"
#import "QNTestConstants.h"

#import "Helpers/XCTestCase+TestJSON.h"

NSString *const kTestAPIKey = @"QNAPIClient_test_api_key";

@interface QNAPIClient (Private)
- (NSDictionary *)enrichParameters:(NSDictionary *)parameters;

- (void)dataTaskWithRequest:(NSURLRequest *)request
                 completion:(void (^)(NSDictionary * _Nullable dict, NSError * _Nullable error))completion;
@end

@interface QNAPIClientTests : XCTestCase

@property (strong, nonatomic) id mockSession;
@property (nonatomic, strong) id request;

@property (nonatomic, strong) QNAPIClient *client;
@end

@implementation QNAPIClientTests

- (void)setUp {
  _mockSession = OCMClassMock([NSURLSession class]);
  _request = OCMClassMock([NSURLRequest class]);
  
  _client = [[QNAPIClient alloc] init];
  
  [_client setSession:_mockSession];
  [_client setApiKey:kTestAPIKey];
}

- (void)tearDown {
  [super tearDown];
  _mockSession = nil;
  _mockSession = nil;
  _client = nil;
}

- (void)testThatEnrichingAddWaitingFields {
  NSDictionary *result = [_client enrichParameters:@{}];
  XCTAssertNotNil(result);
  XCTAssertEqual(result.count, 4);
  XCTAssertNotNil(result[@"access_token"]);
  XCTAssertNotNil(result[@"q_uid"]);
  XCTAssertNotNil(result[@"client_uid"]);
  XCTAssertNotNil(result[@"version"]);
}

- (void)testThatClientSendsRequest {
  [_client dataTaskWithRequest:_request completion:nil];
  
  OCMVerify([self.mockSession dataTaskWithRequest:self.request
                                completionHandler:OCMOCK_ANY]);
}

- (void)testThatClientCallsCompletionHandler {
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  OCMStub([_mockSession dataTaskWithRequest:self.request completionHandler:[OCMArg invokeBlock]]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testThatClientParseNullData {
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
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  
  OCMStub([_mockSession dataTaskWithRequest:self.request
                          completionHandler:([OCMArg invokeBlockWithArgs:[self fileDataFromContentsOfFile:keyQNInitFailedJSON], [NSNull null], [NSNull null], nil])]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    XCTAssertNotNil(dict);
    XCTAssertNil(error);
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

- (void)testThatClientDetectBrokenData {
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  NSData *brokenJson = [self fileDataFromContentsOfFile:keyQNBrokenJSON];
  
  OCMStub([_mockSession dataTaskWithRequest:self.request
                          completionHandler:([OCMArg invokeBlockWithArgs:brokenJson, [NSNull null], [NSNull null], nil])]);
  
  [_client dataTaskWithRequest:_request completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    XCTAssertNil(dict);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 1);
    XCTAssertEqualObjects(error.domain, keyQNErrorDomain);
    [expectation fulfill];
  }];
  
  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

@end
