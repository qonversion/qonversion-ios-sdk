#import <XCTest/XCTest.h>
#import "QNAPIClient.h"

NSString *const kTestAPIKey = @"QNAPIClient_test_api_key";

@interface QNAPIClient (Private)
- (NSDictionary *)enrichParameters:(NSDictionary *)parameters;
@end

@interface QNAPIClientTests : XCTestCase
@property (nonatomic, strong) QNAPIClient *client;
@end

@implementation QNAPIClientTests

- (void)setUp {
  _client = [[QNAPIClient alloc] init];
  [_client setApiKey:kTestAPIKey];
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

@end
