#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "QNDevice.h"
#import "QNInternalConstants.h"
#import "QNDevice+Advertising.h"

// expose private methods for unit testing
@interface QNDevice (Tests)

+ (NSString*)getAdvertiserID:(int) maxAttempts;

@end

@interface QNDeviceTests : XCTestCase
@property (nonatomic, strong) QNDevice *device;
@end

@implementation QNDeviceTests

- (void)setUp {
    _device = [[QNDevice alloc] init];
}

- (void)tearDown {
    _device = nil;
}

- (void)testOSName {
    XCTAssertEqualObjects(@"iOS", _device.osName);
    XCTAssertNotNil(_device.osVersion);
}

- (void)testManufacturer {
    XCTAssertEqualObjects(@"Apple", _device.manufacturer);
}

- (void)testAppVersion {
    XCTAssertNotNil(_device);
    NSString *randomVersion = @"10.11.12";
    
    id mockBundle = [OCMockObject niceMockForClass:[NSBundle class]];
    [[[mockBundle stub] andReturn:mockBundle] mainBundle];
    NSDictionary *mockDictionary = @{@"CFBundleShortVersionString": randomVersion};
    OCMStub([mockBundle infoDictionary]).andReturn(mockDictionary);
    
    XCTAssertEqualObjects(randomVersion, _device.appVersion);
    [mockBundle stopMocking];
}

- (void)testVendorID {
    XCTAssertEqualObjects(_device.vendorID, [[[UIDevice currentDevice] identifierForVendor] UUIDString]);
}

- (void)testAfUserID {
    XCTAssertNil(_device.afUserID);
    XCTAssertNil(_device.adjustUserID);
}

@end
