#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "QNProductCenterManager.h"
#import "QNAPIClient.h"
#import "QNTestConstants.h"
#import "QNLaunchResult.h"

#import "Helpers/XCTestCase+TestJSON.h"

@interface QNProductCenterManager (Private)

@property (nonatomic) QNAPIClient *apiClient;

@end

@interface ProductCenterManagerTests : XCTestCase

@property (nonatomic) id mockClient;
@property (nonatomic) QNProductCenterManager *manager;

@end

@implementation ProductCenterManagerTests

- (void)setUp {
  _mockClient = OCMClassMock([QNAPIClient class]);
  
  _manager = [[QNProductCenterManager alloc] init];
  [_manager setApiClient:_mockClient];
}

- (void)tearDown {
  _manager = nil;
}

- (void)testThatProductCenterGetLaunchModel {
  XCTestExpectation *expectation = [self expectationWithDescription:@""];
  
  OCMStub([_mockClient launchWithCompletion:([OCMArg invokeBlockWithArgs:[self JSONObjectFromContentsOfFile:keyQNInitFullSuccessJSON], [NSNull null], nil])]);
  
  [_manager launch:^(QNLaunchResult * _Nullable result, NSError * _Nullable error) {
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqual(result.permissions.count, 2);
    XCTAssertEqual(result.products.count, 1);
    XCTAssertEqualObjects(result.uid, @"qonversion_user_id");
    
    [expectation fulfill];
  }];

  [self waitForExpectationsWithTimeout:keyQNTestTimeout handler:nil];
}

@end
