#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "QDevice.h"
#import "QConstants.h"

// expose private methods for unit testing
@interface QDevice (Tests)

+ (NSString*)getAdvertiserID:(int) maxAttempts;

@end

@interface QDeviceTests : XCTestCase
@property (nonatomic, strong) QDevice *device;
@end

@implementation QDeviceTests

- (void)setUp {
    _device = [[QDevice alloc] init];
}

- (void)tearDown {
    _device = nil;
}

- (void)testOSName {
    XCTAssertEqualObjects(@"ios", _device.osName);
    XCTAssertNotNil(_device.osVersion);
}

- (void)testModel {
    XCTAssertEqualObjects(@"Simulator", _device.model);
}

- (void)testManufacturer {
    XCTAssertEqualObjects(@"Apple", _device.manufacturer);
}

- (void)testAdvertiserID {
    id mockDeviceInfo = OCMClassMock([QDevice class]);
    [[mockDeviceInfo expect] getAdvertiserID:5];
    XCTAssertEqualObjects(nil, _device.advertiserID);
    [mockDeviceInfo verify];
    [mockDeviceInfo stopMocking];
}

- (void)testAppVersion {
    XCTAssertNotNil(_device);
    
    id mockBundle = [OCMockObject niceMockForClass:[NSBundle class]];
    [[[mockBundle stub] andReturn:mockBundle] mainBundle];
    
    NSDictionary *mockDictionary = @{@"CFBundleShortVersionString": keyQVersion};
    OCMStub([mockBundle infoDictionary]).andReturn(mockDictionary);
    
    XCTAssertEqualObjects(keyQVersion, _device.appVersion);
    [mockBundle stopMocking];
}

- (void)testVendorID {
    XCTAssertEqualObjects(_device.vendorID, [[[UIDevice currentDevice] identifierForVendor] UUIDString]);
}
@end
