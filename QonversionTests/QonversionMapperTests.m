#import <XCTest/XCTest.h>

#import "QNMapper.h"
#import "QONErrors.h"
#import "Helpers/XCTestCase+TestJSON.h"
#import "QNTestConstants.h"

#import "QNMapperObject.h"
#import "QONEntitlement.h"
#import "QONLaunchResult.h"
#import "QONProduct.h"
#import "QONRemoteConfig.h"
#import "QONRemoteConfigMapper.h"
#import "QONRemoteConfigurationSource.h"

@interface QNMapperTests : XCTestCase
@property (nonatomic, strong) NSDictionary *userInitSuccess;
@property (nonatomic, strong) NSDictionary *userInitFailed;
@end

@implementation QNMapperTests

- (void)testRemoteConfigMapperPreservesFrozenAssignmentProvenance {
  NSDictionary *data = @{
    @"payload": @{},
    @"source": @{
      @"uid": @"rc-frozen",
      @"name": @"Frozen config",
      @"type": @"remote_configuration",
      @"assignment_type": @"frozen",
      @"context_key": @""
    }
  };

  QONRemoteConfig *config = [[[QONRemoteConfigMapper alloc] init] mapRemoteConfig:data];

  XCTAssertNotNil(config.source);
  XCTAssertEqual(config.source.assignmentType, QONRemoteConfigurationAssignmentTypeFrozen);
}

- (void)testRemoteConfigAssignmentTypeKeepsExistingNumericValues {
  XCTAssertEqual(QONRemoteConfigurationAssignmentTypeUnknown, -1);
  XCTAssertEqual(QONRemoteConfigurationAssignmentTypeAuto, 0);
  XCTAssertEqual(QONRemoteConfigurationAssignmentTypeManual, 1);
}

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
  QONLaunchResult *result = [QNMapper fillLaunchResult:self.userInitSuccess];
  
  XCTAssertNotNil(result);
  XCTAssertTrue([result.uid isEqualToString:@"qonversion_user_id"]);
  XCTAssertTrue([result.entitlements isKindOfClass:NSDictionary.class]);
  
  QONEntitlement *premium = result.entitlements[@"premium"];
  XCTAssertNotNil(premium);
  XCTAssertTrue(premium.isActive);
  XCTAssertEqual(premium.renewState, QONEntitlementRenewStateBillingIssue);
  
  XCTAssertNotNil(premium.startedDate);
  
  XCTAssertTrue([premium.startedDate.description isEqualToString:@"2020-04-08 18:11:26 +0000"]);
  XCTAssertNotNil(premium.expirationDate);
  XCTAssertTrue(premium.isActive);
  
  XCTAssertTrue([premium.expirationDate.description isEqualToString:@"2020-05-08 14:51:26 +0000"]);
}

- (void)testThatMapperParseFewPermissionsCorrectly {
  QONLaunchResult *result = [QNMapper fillLaunchResult:self.userInitSuccess];
  
  XCTAssertNotNil(result);
  XCTAssertEqual(result.entitlements.count, 2);
  
  QONEntitlement *standart = result.entitlements[@"standart"];
  XCTAssertNotNil(standart);
  XCTAssertTrue([standart.entitlementID isEqualToString:@"standart"]);
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
  
  XCTAssertEqual(brokenResult.error.code, QONErrorCodeInternalError);
}

- (void)testThatMapperParseIntegerFromAnyObject {
  NSInteger value = [QNMapper mapInteger:[NSNull null] orReturn:0];
  XCTAssertTrue(value == 0);
  
  NSDictionary *dict = @{@"key": [NSNull null], @"key_1": @1};
  NSInteger valueFromNull = [QNMapper mapInteger:dict[@"key"] orReturn:0];
  XCTAssertTrue(valueFromNull == 0);
  
  NSInteger valueFromNotExistKey = [QNMapper mapInteger:dict[@"non_exist_key"] orReturn:0];
  XCTAssertTrue(valueFromNotExistKey == 0);
  
  NSInteger valueFromExistValue = [QNMapper mapInteger:dict[@"key_1"] orReturn:0];
  XCTAssertTrue(valueFromExistValue == 1);
}

@end
