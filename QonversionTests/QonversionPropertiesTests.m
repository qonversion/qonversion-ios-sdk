#import <XCTest/XCTest.h>
#import "QNProperties.h"

@interface QNPropertiesTests : XCTestCase

@end

@implementation QNPropertiesTests

- (void)testExample {
  XCTAssertEqualObjects([QNProperties keyForProperty:QONPropertyEmail], @"_q_email");
}

- (void)testCorrectionForPropertyKey {
  XCTAssertTrue([QNProperties checkProperty:@"test"]);
  XCTAssertTrue([QNProperties checkProperty:@"test-test"]);
  XCTAssertTrue([QNProperties checkProperty:@"test-test:"]);
  XCTAssertFalse([QNProperties checkProperty:@"test-test: "]);
  XCTAssertTrue([QNProperties checkProperty:@"test_test"]);
  XCTAssertTrue([QNProperties checkProperty:@"authUID"]);
  XCTAssertTrue([QNProperties checkProperty:@"appsFlyerID"]);
  XCTAssertTrue([QNProperties checkProperty:@"appsFlyer_ID"]);
}

@end
