#import <XCTest/XCTest.h>
#import "QNRequestBuilder.h"
#import "QNAPIConstants.h"

@interface QNRequestBuilderTests : XCTestCase
@property (nonatomic, strong) QNRequestBuilder *requestBuilder;
@end

@interface QNRequestBuilder (Private)

- (NSMutableURLRequest *)baseRequestWithURL:(NSURL *)url type:(NSString *)type;

@end

@implementation QNRequestBuilderTests

- (void)setUp {
  _requestBuilder = [[QNRequestBuilder alloc] init];
  [_requestBuilder setBaseURL:kAPIBase];
}

- (void)tearDown {
  _requestBuilder = nil;
}

- (void)testThatBuilderSetCorrectRequestSettings {
  NSURL *url = [[NSURL alloc] initWithString:@"https://api.qonversion.io/"];
  NSURLRequest *request = [_requestBuilder baseRequestWithURL:url type:@"POST"];
  
  XCTAssertEqualObjects(request.HTTPMethod, @"POST");
  NSString *contentType = [request.allHTTPHeaderFields valueForKey:@"Content-Type"];
  
  XCTAssertNotNil(contentType);
  XCTAssertEqualObjects(contentType, @"application/json; charset=utf-8");
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

@end
