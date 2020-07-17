#import <XCTest/XCTest.h>

#import "QNMapper.h"
#import "QNErrors.h"
#import "Helpers/XCTestCase+TestJSON.h"
#import "QNTestConstants.h"

#import "QNMapperObject.h"
#import "QNLaunchResult.h"

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
  QNLaunchResult *result = [QNMapper fillLaunchResult:self.userInitSuccess];
  
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
  QNLaunchResult *result = [QNMapper fillLaunchResult:self.userInitSuccess];
  
  XCTAssertNotNil(result);
  XCTAssertEqual(result.permissions.count, 2);
  
  QNPermission *standart = result.permissions[@"standart"];
  XCTAssertNotNil(standart);
  XCTAssertTrue([standart.permissionID isEqualToString:@"standart"]);
  XCTAssertFalse(standart.isActive);
}

- (void)testThatMapperParsePermissionWithBrokenJson {
  
  QNMapperObject *result = [QNMapper mapperObjectFrom:[self JSONObjectFromContentsOfFile:keyQNInitFailedJSON]];
  
  XCTAssertNotNil(result);
  XCTAssertNotNil(result.error);
  XCTAssertNil(result.data);
  
  QNMapperObject *brokenResult = [QNMapper mapperObjectFrom:nil];
  XCTAssertNotNil(brokenResult);
  XCTAssertNil(brokenResult.data);
  XCTAssertNotNil(brokenResult.error);
  
  XCTAssertEqual(brokenResult.error.code, QNErrorInternalError);
}

- (void)testThatMapperParseIntegerFromAnyObject {
  NSInteger value = [QNMapper mapInteger:[NSNull null]];
  XCTAssertTrue(value == 0);
  
  NSDictionary *dict = @{@"key": [NSNull null], @"key_1": @1};
  NSInteger valueFromNull = [QNMapper mapInteger:dict[@"key"]];
  XCTAssertTrue(valueFromNull == 0);
  
  NSInteger valueFromNotExistKey = [QNMapper mapInteger:dict[@"non_exist_key"]];
  XCTAssertTrue(valueFromNotExistKey == 0);
  
  NSInteger valueFromExistValue = [QNMapper mapInteger:dict[@"key_1"]];
  XCTAssertTrue(valueFromExistValue == 1);
}

@end
