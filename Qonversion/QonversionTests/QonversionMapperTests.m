#import <XCTest/XCTest.h>
#import "QonversionMapper.h"
#import "Helpers/XCTestCase+TestJSON.h"


static NSString *JSONWithActiveProduct = @"check_result_with_active_users.json";

@interface QonversionMapperTests : XCTestCase
@property (nonatomic, strong) NSDictionary *activeUserDict;
@end

@implementation QonversionMapperTests

- (void)setUp {
    [super setUp];
    
    self.activeUserDict =  [self JSONObjectFromContentsOfFile:JSONWithActiveProduct];
}

- (void)tearDown {
    self.activeUserDict = nil;
    [super tearDown];
}

- (void)testThatAllRequiredDataPrepared {
    XCTAssertNotNil([self activeUserDict]);
}

- (void)testThatMapper {
    QonversionCheckResult *activeUserResult = [[QonversionMapper new] fillCheckResultWith:self.activeUserDict];
    XCTAssertNotNil(activeUserResult);
    
    NSUInteger timestamp = 1586369519;
    ClientEnvironment environment = ClientEnvironmentProduction;
    
    XCTAssertEqual(activeUserResult.timestamp, timestamp);
    XCTAssertEqual(activeUserResult.environment, environment);
    XCTAssertEqual(activeUserResult.activeProducts.count, 1);
    XCTAssertEqual(activeUserResult.allProducts.count, 1);
}

@end



































