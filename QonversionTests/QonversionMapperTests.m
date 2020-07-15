#import <XCTest/XCTest.h>

#import "QNMapper.h"
#import "Helpers/XCTestCase+TestJSON.h"
#import "QNTestConstants.h"

@interface QNMapperTests : XCTestCase
@property (nonatomic, strong) NSDictionary *userInitSuccess;
@property (nonatomic, strong) NSDictionary *userInitFailed;
@end

@implementation QNMapperTests

- (void)setUp {
    [super setUp];
    
    self.userInitSuccess = [self JSONObjectFromContentsOfFile:keyQNInitSuccessJSON];
    self.userInitFailed = [self JSONObjectFromContentsOfFile:keyQNInitFailedJSON];
}

- (void)tearDown {
    self.userInitSuccess = nil;
    self.userInitFailed = nil;
    
    [super tearDown];
}

- (void)testThatMapperParsePermissions {
    QNLaunchResult *result = [[QNMapper new] fillLaunchResult:self.userInitSuccess];
    
    XCTAssertNotNil(result);
    XCTAssertTrue([result.uid isEqualToString:@"qonversion_user_id"]);
    XCTAssertTrue([result.permissions isKindOfClass:NSDictionary.class]);
    
    QNPermission *premium = result.permissions[@"premium"];
    XCTAssertNotNil(premium);
    XCTAssertTrue(premium.isActive);
    XCTAssertEqual(premium.renewState, QNPermissionRenewStateBillingIssue);
    
    XCTAssertNotNil(premium.startedDate);
    
    XCTAssertTrue([premium.startedDate.description isEqualToString:@"2020-04-08 18:11:26 +0000"]);
    XCTAssertNotNil(premium.expirationDate);
    XCTAssertTrue(premium.isActive);
    
    XCTAssertTrue([premium.expirationDate.description isEqualToString:@"2020-05-08 14:51:26 +0000"]);
}

- (void)testThatMapperParseFewPermissionsCorrectly {
    QNLaunchResult *result = [[QNMapper new] fillLaunchResult:self.userInitSuccess];
      
    XCTAssertNotNil(result);
    XCTAssertEqual(result.permissions.count, 2);
    
    QNPermission *standart = result.permissions[@"standart"];
    XCTAssertNotNil(standart);
    XCTAssertTrue([standart.permissionID isEqualToString:@"standart"]);
    XCTAssertFalse(standart.isActive);
}

- (void)testThatMapparParsePermissionWithBrokenJson {
    QonversionLaunchComposeModel *result = [[QNMapper new] composeLaunchModelFrom:[self fileDataFromContentsOfFile:keyQNInitFailedJSON]];
    
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
