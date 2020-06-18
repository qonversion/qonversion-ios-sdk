#import <XCTest/XCTest.h>
#import "QRequestBuilder.h"

@interface QRequestBuilderTests : XCTestCase
@property (nonatomic, strong) QRequestBuilder *requestBuilder;
@end

@implementation QRequestBuilderTests

- (void)setUp {
    _requestBuilder = [[QRequestBuilder alloc] initWithKey:@"API_KEY"];
}

- (void)tearDown {
    _requestBuilder = nil;
}

- (void)testThatInitRequestBuilderSetCorrectURL {
    NSURLRequest *request = [_requestBuilder makeInitRequestWith:@{}];
    XCTAssertNotNil(request);
    
    XCTAssertNotNil(request.URL);
    XCTAssertEqualObjects(request.URL.absoluteString, @"https://api.qonversion.io/v1/user/init");
}

- (void)testThatPurchaseRequestBuilderSetCorrectURL {
    NSURLRequest *request = [_requestBuilder makePurchaseRequestWith:@{}];
    XCTAssertNotNil(request);
    
    XCTAssertNotNil(request.URL);
    XCTAssertEqualObjects(request.URL.absoluteString, @"https://api.qonversion.io/purchase");
}

- (void)testThatCheckRequestBuilderSetCorrectURL {
    NSURLRequest *request = [_requestBuilder makeCheckRequest];
    XCTAssertNotNil(request);
    
    XCTAssertNotNil(request.URL);
    XCTAssertEqualObjects(request.URL.absoluteString, @"https://api.qonversion.io/check");
}

@end
