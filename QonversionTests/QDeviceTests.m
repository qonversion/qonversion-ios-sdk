#import <XCTest/XCTest.h>
#import "QDevice.h"

@interface QDeviceTests : XCTestCase
@property (nonatomic, strong) QDevice *device;
@end

@implementation QDeviceTests

- (void)setUp {
    self.device = [[QDevice alloc] init];
}

- (void)tearDown {
    self.device = nil;
}

- (void)testThatDevice {
    XCTAssertNotNil(self.device);
    XCTAssertEqualObjects(@"ios", self.device.osName);
    
    XCTAssertNotNil(self.device.appVersion);
    XCTAssertNotNil(self.device.osVersion);
}
@end
