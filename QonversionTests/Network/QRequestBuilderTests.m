#import <XCTest/XCTest.h>
#import "QNRequestBuilder.h"

@interface QNRequestBuilderTests : XCTestCase
@property (nonatomic, strong) QNRequestBuilder *requestBuilder;
@end

@implementation QNRequestBuilderTests

- (void)setUp {
    _requestBuilder = [[QNRequestBuilder alloc] initWithKey:@"API_KEY"];
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
    XCTAssertEqualObjects(request.URL.absoluteString, @"https://api.qonversion.io/v1/user/purchase");
}

- (void)testThatCheckRequestBuilderSetCorrectURL {
    NSURLRequest *request = [_requestBuilder makeCheckRequest];
    XCTAssertNotNil(request);
    
    XCTAssertNotNil(request.URL);
    XCTAssertEqualObjects(request.URL.absoluteString, @"https://api.qonversion.io/check");
}

@end
