#import <XCTest/XCTest.h>
#import "QonversionMapper.h"
#import "Helpers/XCTestCase+TestJSON.h"


static NSString *JSONWithActiveProduct = @"check_result_with_active_product.json";
static NSString *JSONWithoutProducts = @"check_restul_without_products.json";

@interface QonversionMapperTests : XCTestCase
@property (nonatomic, strong) NSDictionary *activeUserDict;
@property (nonatomic, strong) NSDictionary *withoutProducts;
@end

@implementation QonversionMapperTests

- (void)setUp {
    [super setUp];
    
    self.activeUserDict = [self JSONObjectFromContentsOfFile:JSONWithActiveProduct];
    self.withoutProducts = [self JSONObjectFromContentsOfFile:JSONWithoutProducts];
}

- (void)tearDown {
    self.activeUserDict = nil;
    self.withoutProducts = nil;
    [super tearDown];
}

- (void)testThatAllRequiredDataPrepared {
    XCTAssertNotNil([self activeUserDict]);
    XCTAssertNotNil([self withoutProducts]);
}

- (void)testThatMapperWorkCorrectWithIdealJSON {
    QonversionCheckResult *activeUserResult = [[QonversionMapper new] fillCheckResultWith:self.activeUserDict];
    XCTAssertNotNil(activeUserResult);
    
    NSUInteger timestamp = 1586369519;
    ClientEnvironment environment = ClientEnvironmentProduction;
    
    XCTAssertEqual(activeUserResult.timestamp, timestamp);
    XCTAssertEqual(activeUserResult.environment, environment);
    XCTAssertEqual(activeUserResult.activeProducts.count, 1);
    XCTAssertEqual(activeUserResult.allProducts.count, 1);
    
    XCTAssertNotNil(activeUserResult.activeProducts.firstObject);
    
    XCTAssertEqual(activeUserResult.activeProducts.firstObject.billingRetry, NO);
    XCTAssertEqual(activeUserResult.activeProducts.firstObject.expired, NO);
}

- (void)testThatMapperParseEmptyProductCorrectly {
    QonversionCheckResult *resultWithoutProducts = [[QonversionMapper new] fillCheckResultWith:self.withoutProducts];
    XCTAssertNotNil(resultWithoutProducts);
    
    XCTAssertEqual(resultWithoutProducts.activeProducts.count, 0);
    XCTAssertEqual(resultWithoutProducts.allProducts.count, 0);
}

@end



































