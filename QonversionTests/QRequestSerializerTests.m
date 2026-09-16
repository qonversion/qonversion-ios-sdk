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

- (void)testThatEachRetryHasOnlyItsCurrentAttemptNumber {
    NSMutableURLRequest *initialRequest = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://example.invalid/v1/user/init"]];
    initialRequest.HTTPMethod = @"POST";
    initialRequest.HTTPBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    [initialRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLRequest *request = initialRequest;

    // QNAPIClient passes the already annotated request to the next retry.
    for (NSInteger tryCount = 0; tryCount < 4; tryCount++) {
        NSURLRequest *previousRequest = request;
        NSString *previousAttempt = [previousRequest valueForHTTPHeaderField:@"Attempt"];
        request = [self.serializer addTryCountToHeader:@(tryCount) request:previousRequest];

        XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Attempt"],
                              [NSString stringWithFormat:@"%ld", (long)tryCount + 1]);
        XCTAssertEqualObjects([previousRequest valueForHTTPHeaderField:@"Attempt"], previousAttempt);
        XCTAssertEqualObjects(request.URL, initialRequest.URL);
        XCTAssertEqualObjects(request.HTTPMethod, initialRequest.HTTPMethod);
        XCTAssertEqualObjects(request.HTTPBody, initialRequest.HTTPBody);
        XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Content-Type"], @"application/json");
    }
    XCTAssertNil([initialRequest valueForHTTPHeaderField:@"Attempt"]);
}

- (void)testThatStoredRequestReplayReplacesAccumulatedAttempts {
    NSMutableURLRequest *storedRequest = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://example.invalid/v1/user/init"]];
    [storedRequest setValue:@"1,2,3,4" forHTTPHeaderField:@"Attempt"];

    NSURLRequest *request = [self.serializer addTryCountToHeader:@0 request:storedRequest];

    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Attempt"], @"1");
    XCTAssertEqualObjects([storedRequest valueForHTTPHeaderField:@"Attempt"], @"1,2,3,4");
}

@end
