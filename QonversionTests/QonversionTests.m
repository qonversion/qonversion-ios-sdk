#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "Qonversion.h"
#import "XCTestCase+TestJSON.h"
#import "UserInfo.h"

@interface Qonversion (Tests)

+ (NSURLRequest *)makePostRequestWithEndpoint:(NSString *)endpoint andBody:(NSDictionary *)body;

@end

@interface QonversionTests : XCTestCase

@end

@implementation QonversionTests

- (void)setUp {
    [super setUp];
    
    // Set default value before
    [Qonversion setDebugMode:NO];
}

- (void)testThatDebugModeSetDefaultValueAsNoCorrectly {
    id mockUserInfo = [OCMockObject niceMockForClass:[UserInfo class]];
    
    NSDictionary *mockDictionary = @{@"d": @""};
    OCMStub([mockUserInfo overallData]).andReturn(mockDictionary);
    
    [Qonversion launchWithKey:@"key" completion:nil];
    
    NSURLRequest *request = [Qonversion makePostRequestWithEndpoint:@"dummy" andBody:@{}];
    XCTAssertNotNil(request);
    NSDictionary *body = [self JSONObjectFromData:request.HTTPBody];
    XCTAssertNotNil(body);

    NSNumber *debugMode = body[@"debug_mode"];
    XCTAssertEqual(debugMode.copy, @NO);
}

- (void)testThatDebugModeSetCorrectly {
    id mockUserInfo = [OCMockObject niceMockForClass:[UserInfo class]];
    
    NSDictionary *mockDictionary = @{@"d": @""};
    OCMStub([mockUserInfo overallData]).andReturn(mockDictionary);
    [Qonversion setDebugMode:YES];
    [Qonversion launchWithKey:@"key" userID:@"user"];
    NSURLRequest *request = [Qonversion makePostRequestWithEndpoint:@"dummy" andBody:@{}];
    XCTAssertNotNil(request);
    NSDictionary *body = [self JSONObjectFromData:request.HTTPBody];
    XCTAssertNotNil(body);

    NSNumber *debugMode = body[@"debug_mode"];
    XCTAssertEqual(debugMode, @YES);
}

@end
