#import <XCTest/XCTest.h>

#import "QNMapper.h"
#import "Helpers/XCTestCase+TestJSON.h"

static NSString *checkFailedState = @"check_failed_state.json";
static NSString *initSuccessJSON = @"init.json";
static NSString *initFailedJSON = @"init_failed_state.json";

@interface QNMapperTests : XCTestCase
@property (nonatomic, strong) NSDictionary *userInitSuccess;
@property (nonatomic, strong) NSDictionary *userInitFailed;
@end

@implementation QNMapperTests

- (void)setUp {
    [super setUp];
    
    self.userInitSuccess = [self JSONObjectFromContentsOfFile:initSuccessJSON];
    self.userInitFailed = [self JSONObjectFromContentsOfFile:initFailedJSON];
}

- (void)tearDown {
    self.userInitSuccess = nil;
    self.userInitFailed = nil;
    
    [super tearDown];
}

- (void)testThatMapperParsePermissions {
    QonversionLaunchResult *result = [[QNMapper new] fillLaunchResult:self.userInitSuccess];
    
    XCTAssertNotNil(result);
    XCTAssertTrue([result.uid isEqualToString:@"qonversion_user_id"]);
    XCTAssertTrue([result.permissions isKindOfClass:NSDictionary.class]);
    
    QonversionPermission *premium = result.permissions[@"premium"];
    XCTAssertNotNil(premium);
    XCTAssertTrue(premium.isActive);
    XCTAssertEqual(premium.renewState, QonversionPermissionRenewStateBillingIssue);
    
    XCTAssertNotNil(premium.startedDate);
    
    XCTAssertTrue([premium.startedDate.description isEqualToString:@"2020-04-08 18:11:26 +0000"]);
    XCTAssertNotNil(premium.expirationDate);
    XCTAssertTrue(premium.isActive);
    
    XCTAssertTrue([premium.expirationDate.description isEqualToString:@"2020-05-08 14:51:26 +0000"]);
}

- (void)testThatMapperParseFewPermissionsCorrectly {
    QonversionLaunchResult *result = [[QNMapper new] fillLaunchResult:self.userInitSuccess];
      
    XCTAssertNotNil(result);
    XCTAssertEqual(result.permissions.count, 2);
    
    QonversionPermission *standart = result.permissions[@"standart"];
    XCTAssertNotNil(standart);
    XCTAssertTrue([standart.permissionID isEqualToString:@"standart"]);
    XCTAssertFalse(standart.isActive);
}

- (void)testThatMapparParsePermissionWithBrokenJson {
    QonversionLaunchComposeModel *result = [[QNMapper new] composeLaunchModelFrom:[self fileDataFromContentsOfFile:initFailedJSON]];
    
    XCTAssertNotNil(result);
    XCTAssertNotNil(result.error);
    XCTAssertNil(result.result);
    XCTAssertEqual(result.result.permissions.count, 0);
    
    QonversionLaunchComposeModel *brokenResult = [[QNMapper new] composeLaunchModelFrom:NULL];
    XCTAssertNotNil(brokenResult);
    XCTAssertNil(brokenResult.result);
    XCTAssertNotNil(brokenResult.error);
}

@end
