#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNAPIClient.h"


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

- (void)testThatRequestHandler {
  
}

@end
