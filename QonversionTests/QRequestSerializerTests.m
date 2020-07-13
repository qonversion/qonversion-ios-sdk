#import <XCTest/XCTest.h>
#import "QNRequestSerializer.h"

@interface QNRequestSerializerTests : XCTestCase

@property (nonatomic, strong) QNRequestSerializer *serializer;

@end
  
@implementation QNRequestSerializerTests

- (void)setUp {
    [super setUp];
    
    self.serializer = [[QNRequestSerializer alloc] init];
}

- (void)testThatLaunchDataCorrect {
    id launchData = self.serializer.launchData;
    XCTAssertTrue([launchData isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(launchData);
}

@end
