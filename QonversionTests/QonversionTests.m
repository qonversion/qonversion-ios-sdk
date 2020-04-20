#import <XCTest/XCTest.h>
#import "Qonversion.h"

@interface Qonversion (Tests)
+ (NSURLRequest *)makePostRequestWithEndpoint:(NSString *)endpoint andBody:(NSDictionary *)body;
@end

@interface QonversionTests : XCTestCase

@end

@implementation QonversionTests

- (void)testThatDebugModeSetCorrectly {
    [Qonversion setDebugMode:YES];
    [Qonversion launchWithKey:@"key" userID:@"user"];
    NSURLRequest *request = [Qonversion makePostRequestWithEndpoint:@"dummy" andBody:@{}];
    XCTAssertNotNil(request);
    
    NSError* error;
    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody
                                                         options:kNilOptions
                                                           error:&error];
    
}

@end
