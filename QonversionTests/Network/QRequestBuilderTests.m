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
    NSURLRequest *initRequest = [_requestBuilder makeInitRequestWith:@{}];
    
    XCTAssertNotNil(initRequest.URL);
    XCTAssertEqualObjects(initRequest.URL.absoluteString, @"https://api.qonversion.io/v1/user/init");
}

- (void)testThatPurchaseRequestBuilderSetCorrectURL {
    NSURLRequest *initRequest = [_requestBuilder makePurchaseRequestWith:@{}];
    
    XCTAssertNotNil(initRequest.URL);
    XCTAssertEqualObjects(initRequest.URL.absoluteString, @"https://api.qonversion.io/purchase");
}

- (void)testThatCheckRequestBuilderSetCorrectURL {
    NSURLRequest *initRequest = [_requestBuilder makeCheckRequest];
    
    XCTAssertNotNil(initRequest.URL);
    XCTAssertEqualObjects(initRequest.URL.absoluteString, @"https://api.qonversion.io/check");
}

@end
