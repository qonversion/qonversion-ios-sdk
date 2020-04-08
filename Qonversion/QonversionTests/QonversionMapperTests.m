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

@end

