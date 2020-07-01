#import <XCTest/XCTest.h>
#import "QRequestSerializer.h"

@interface QRequestSerializerTests : XCTestCase

@property (nonatomic, strong) QRequestSerializer *serializer;

@end


@implementation QRequestSerializerTests

- (void)setUp {
    [super setUp];
    
    self.serializer = [[QRequestSerializer alloc] initWithUserID:@"test"];
}

- (void)testThatLaunchDataCorrect {
    id launchData = self.serializer.launchData;
    XCTAssertTrue([launchData isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(launchData);
}

@end
