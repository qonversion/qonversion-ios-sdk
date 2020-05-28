#import <XCTest/XCTest.h>
#import "QonversionProperties.h"

@interface QonversionPropertiesTests : XCTestCase

@end

@implementation QonversionPropertiesTests

- (void)testExample {
    XCTAssertEqualObjects([QonversionProperties keyForProperty:QPropertyEmail], @"_q_email");
}

- (void)testCorrectionForPropertyKey {
    XCTAssertTrue([QonversionProperties checkProperty:@"test"]);
    XCTAssertTrue([QonversionProperties checkProperty:@"test-test"]);
    XCTAssertTrue([QonversionProperties checkProperty:@"test-test:"]);
    XCTAssertFalse([QonversionProperties checkProperty:@"test-test: "]);
    XCTAssertTrue([QonversionProperties checkProperty:@"test_test"]);
}

@end
