#import <XCTest/XCTest.h>
#import "QNProperties.h"

@interface QNPropertiesTests : XCTestCase

@end

@implementation QNPropertiesTests

- (void)testExample {
    XCTAssertEqualObjects([QNProperties keyForProperty:QNPropertyEmail], @"_q_email");
}

- (void)testCorrectionForPropertyKey {
    XCTAssertTrue([QNProperties checkProperty:@"test"]);
    XCTAssertTrue([QNProperties checkProperty:@"test-test"]);
    XCTAssertTrue([QNProperties checkProperty:@"test-test:"]);
    XCTAssertFalse([QNProperties checkProperty:@"test-test: "]);
    XCTAssertTrue([QNProperties checkProperty:@"test_test"]);
}

@end
