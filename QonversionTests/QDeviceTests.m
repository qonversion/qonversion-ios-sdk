#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "QNDevice.h"
#import "QNConstants.h"
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

- (void)testModel {
    XCTAssertEqualObjects(@"x86_64", _device.model);
}

- (void)testManufacturer {
    XCTAssertEqualObjects(@"Apple", _device.manufacturer);
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

- (void)testLanguage {
    XCTAssertEqualObjects(@"English", _device.language);
}

- (void)testAfUserID {
    XCTAssertNil(_device.afUserID);
    XCTAssertNil(_device.adjustUserID);
}

@end
