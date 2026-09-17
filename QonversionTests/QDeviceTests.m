#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "QNDevice.h"
#import "QNInternalConstants.h"
#import "QNAdvertisingIdProvider.h"

// expose private state for unit testing
@interface QNDevice (Tests)

@property (assign, nonatomic) BOOL idfaProhibited;

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

// The IDFA reader is a separate compilation unit that QNDevice finds at runtime (the Swift package product
// `QonversionNoIdfa` and the `NoIdfa` pod subspec ship without it). These tests run against the full build.

- (void)testAdvertisingIdProvider_isDiscoverableAtRuntime {
    Class provider = NSClassFromString(@"QNAdvertisingIdProvider");
    XCTAssertNotNil(provider);
    XCTAssertTrue([provider respondsToSelector:NSSelectorFromString(@"obtainAdvertisingID")]);
}

- (void)testAdvertisingIdProvider_returnsNilOrUUID {
    NSString *identifier = [QNAdvertisingIdProvider obtainAdvertisingID];
    if (identifier) {
        XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:identifier]);
        XCTAssertNotEqualObjects(identifier, @"00000000-0000-0000-0000-000000000000");
    }
}

- (void)testAdvertiserID_withProviderPresent_isNotProhibited {
    XCTAssertFalse(_device.idfaProhibited);
    NSString *advertiserID = _device.advertiserID;
    // With the provider linked the lookup succeeds; whether an identifier comes back depends on the simulator.
    XCTAssertFalse(_device.idfaProhibited);
    XCTAssertEqualObjects(advertiserID, [QNAdvertisingIdProvider obtainAdvertisingID]);
}

@end
