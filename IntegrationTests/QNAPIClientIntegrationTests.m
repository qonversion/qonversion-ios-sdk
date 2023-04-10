//
//  QNAPIClientIntegrationTests.m
//  QonversionTests
//
//  Created by Kamo Spertsyan on 29.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "QNAPIClient.h"
#import "QNAPIConstants.h"
#import "QNProperties.h"
#import "QNTestConstants.h"
#import "Helpers/XCTestCase+TestJSON.h"

NSString *const kSDKVersion = @"10.11.12";
NSString *const kProjectKey = @"V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-a";
NSString *const kIncorrectProjectKey = @"V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-aaaa";
const int kRequestTimeout = 10;

@interface QNAPIClientIntegrationTests : XCTestCase

@property (nonatomic, copy) NSString *kUidPrefix;
@property (nonatomic, copy) NSDictionary *monthlyProduct;
@property (nonatomic, copy) NSDictionary *annualProduct;
@property (nonatomic, copy) NSDictionary *inappProduct;
@property (nonatomic, copy) NSDictionary *expectedOffering;
@property (nonatomic, copy) NSDictionary *expectedProductPermissions;
@property (nonatomic, copy) NSArray *expectedProducts;
@property (nonatomic, copy) NSArray *expectedOfferings;
@property (nonatomic, copy) NSArray *expectedPermissions;
@property (nonatomic, copy) NSDictionary *mainRequestData;
@property (nonatomic, copy) NSDictionary *purchaseData;
@property (nonatomic, copy) NSString *noCodeScreenId;

@end

@implementation QNAPIClientIntegrationTests

- (void)setUp {
  NSString *timestamp = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
  self.kUidPrefix = [NSString stringWithFormat:@"%@%@", @"QON_test_uid_ios_", timestamp];

  self.monthlyProduct = @{
    @"duration": @1,
    @"id": @"test_monthly",
    @"store_id": @"apple_monthly",
    @"type": @1,
  };
  
  self.annualProduct = @{
    @"duration": @4,
    @"id": @"test_annual",
    @"store_id": @"apple_annual",
    @"type": @0,
  };
  
  self.inappProduct = @{
    @"duration": [NSNull null],
    @"id": @"test_inapp",
    @"store_id": @"apple_inapp",
    @"type": @2,
  };
  
  self.expectedProducts = @[self.monthlyProduct, self.annualProduct, self.inappProduct];
  
  self.expectedOffering = @{
    @"id": @"main",
    @"products": @[self.annualProduct, self.monthlyProduct],
    @"tag": @1,
  };
  
  self.expectedOfferings = @[self.expectedOffering];
  
  self.expectedProductPermissions = @{
    self.annualProduct[@"id"]: @[@"premium"],
    self.monthlyProduct[@"id"]: @[@"premium"],
    self.inappProduct[@"id"]: @[@"noAds"],
  };
  
  self.expectedPermissions = @[
    @{
      @"active": @0,
      @"associated_product": @"test_monthly",
      @"current_period_type": @"regular",
      @"expiration_timestamp": @1680250473,
      @"id": @"premium",
      @"renew_state": @2,
      @"source": @"appstore",
      @"started_timestamp": @1680246795,
    },
  ];
  
  self.mainRequestData = [self dictionaryFromContentsOfFile:keyQNInitRequestMainDataJSON];

  NSMutableDictionary *requestData = [self.mainRequestData mutableCopy];
  requestData[@"purchase"] = @{
    @"country": @"USA",
    @"currency": @"USD",
    @"experiment": @{},
    @"original_transaction_id": @"",
    @"period_number_of_units": @1,
    @"period_unit": @2,
    @"product": @"apple_monthly",
    @"product_id": @"test_monthly",
    @"transaction_id": @2000000305530406,
    @"value": @"4.99",
  };

  self.purchaseData = requestData;
  
  self.noCodeScreenId = @"lsarjYcU";
}

- (void)testInit {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Init call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_init"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    XCTAssertNotNil(res);
    XCTAssertNil(error);
    XCTAssertTrue(res[@"success"]);
    XCTAssertTrue([uid isEqualToString:res[@"data"][@"uid"]]);
    XCTAssertTrue([self areArraysDeepEqual:self.expectedProducts second:res[@"data"][@"products"]]);
    XCTAssertTrue([self areArraysDeepEqual:self.expectedOfferings second:res[@"data"][@"offerings"]]);
    XCTAssertTrue([self areArraysDeepEqual:@[] second:res[@"data"][@"permissions"]]);
    XCTAssertTrue([self areDictionariesDeepEqual:self.expectedProductPermissions second:res[@"data"][@"products_permissions"]]);
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testInitError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Init error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_init"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];

  // when
  [client launchRequest:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertProjectNotFoundError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testPurchase {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Purchase call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_purchase"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client purchaseRequestWith:self.purchaseData completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue(res[@"success"]);
      XCTAssertTrue([uid isEqualToString:res[@"data"][@"uid"]]);
      XCTAssertTrue([self areArraysDeepEqual:self.expectedProducts second:res[@"data"][@"products"]]);
      XCTAssertTrue([self areArraysDeepEqual:self.expectedOfferings second:res[@"data"][@"offerings"]]);
      XCTAssertTrue([self areArraysDeepEqual:self.expectedPermissions second:res[@"data"][@"permissions"]]);
      XCTAssertTrue([self areDictionariesDeepEqual:@{} second:res[@"data"][@"products_permissions"]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testPurchaseForExistingUser {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Purchase call for existing user"];
  NSString *uid = @"QON_0b091d1aa58f44beb8dc30c765729484";
  QNAPIClient *client = [self getClient:uid];

  // when
  [client purchaseRequestWith:self.purchaseData completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    XCTAssertNotNil(res);
    XCTAssertNil(error);
    XCTAssertTrue(res[@"success"]);
    XCTAssertTrue([uid isEqualToString:res[@"data"][@"uid"]]);
    XCTAssertTrue([self areArraysDeepEqual:self.expectedProducts second:res[@"data"][@"products"]]);
    XCTAssertTrue([self areArraysDeepEqual:self.expectedOfferings second:res[@"data"][@"offerings"]]);
    XCTAssertTrue([self areArraysDeepEqual:self.expectedPermissions second:res[@"data"][@"permissions"]]);
    XCTAssertTrue([self areDictionariesDeepEqual:@{} second:res[@"data"][@"products_permissions"]]);
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testPurchaseError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Purchase error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_purchase"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  // when
  [client purchaseRequestWith:self.purchaseData completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertProjectNotFoundError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testAttribution {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Attribution call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_attribution"];
  QNAPIClient *client = [self getClient:uid];
  
  NSDictionary *data = @{
    @"one": @"two",
    @"number": @42,
  };
  
  NSDictionary *expRes = @{
    @"data": @{
      @"status": @"OK",
    },
    @"success": @1,
  };

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client attributionRequest:QONAttributionProviderAdjust data:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue([self areDictionariesDeepEqual:expRes second:res]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testAttributionError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Attribution error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_attribution"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  NSDictionary *data = @{
    @"one": @"two",
    @"number": @42,
  };

  // when
  [client attributionRequest:QONAttributionProviderAdjust data:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertProjectNotFoundError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testProperties {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Properties call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_properties"];
  QNAPIClient *client = [self getClient:uid];
  
  NSDictionary *data = @{
    @"customProperty": @"custom property value",
    [QNProperties keyForProperty:QONPropertyUserID]: @"custom user id",
  };
  
  NSDictionary *expRes = @{
    @"data": @{},
    @"success": @1,
  };

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client properties:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue([self areDictionariesDeepEqual:expRes second:res]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testPropertiesError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Properties error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_properties"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  NSDictionary *data = @{
    @"customProperty": @"custom property value",
    [QNProperties keyForProperty:QONPropertyUserID]: @"custom user id",
  };

  // when
  [client properties:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testCheckTrialIntroEligibility {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"CheckTrialIntroEligibility call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_checkTrialIntroEligibility"];
  QNAPIClient *client = [self getClient:uid];
  
  NSMutableDictionary *data = [_mainRequestData mutableCopy];
  data[@"products_local_data"] = @[
    @{
      @"store_id": @"apple_annual",
      @"subscription_group_identifier": @20679497,
    },
    @{
      @"store_id": @"apple_inapp",
      @"subscription_group_identifier": @20679497,
    },
    @{
      @"store_id": @"apple_monthly",
      @"subscription_group_identifier": @20679497,
    }
  ];
  
  NSDictionary *expRes = @{
    @"products_enriched": @[
      @{
        @"intro_eligibility_status": @"non_intro_or_trial_product",
        @"product": @{
          @"duration": @1,
          @"id": @"test_monthly",
          @"store_id": @"apple_monthly",
          @"type": @1,
        },
      },
      @{
        @"intro_eligibility_status": @"intro_or_trial_eligible",
        @"product": @{
          @"duration": @4,
          @"id": @"test_annual",
          @"store_id": @"apple_annual",
          @"type": @0,
        },
      },
      @{
        @"intro_eligibility_status": @"non_intro_or_trial_product",
        @"product": @{
          @"duration": [NSNull null],
          @"id": @"test_inapp",
          @"store_id": @"apple_inapp",
          @"type": @2,
        },
      },
    ],
  };

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client checkTrialIntroEligibilityParamsForData:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue(res[@"success"]);
      XCTAssertTrue([self areDictionariesDeepEqual:expRes second:res[@"data"]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testCheckTrialIntroEligibilityError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"CheckTrialIntroEligibility error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_checkTrialIntroEligibility"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  NSMutableDictionary *data = [_mainRequestData mutableCopy];
  data[@"products_local_data"] = @[
    @{
      @"store_id": @"apple_annual",
      @"subscription_group_identifier": @20679497,
    },
    @{
      @"store_id": @"apple_inapp",
      @"subscription_group_identifier": @20679497,
    },
    @{
      @"store_id": @"apple_monthly",
      @"subscription_group_identifier": @20679497,
    }
  ];

  // when
  [client checkTrialIntroEligibilityParamsForData:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertProjectNotFoundError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testIdentify {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Identify call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_identify"];
  NSString *identityId = [NSString stringWithFormat:@"%@%@", @"identity_for_", uid];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client createIdentityForUserID:identityId anonUserID:uid completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue(res[@"success"]);
      XCTAssertTrue([uid isEqualToString:res[@"data"][@"anon_id"]]);
      XCTAssertTrue([identityId isEqualToString:res[@"data"][@"identity_id"]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testIdentifyError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Identify error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_identify"];
  NSString *identityId = [NSString stringWithFormat:@"%@%@", @"identity_for_", uid];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  // when
  [client createIdentityForUserID:identityId anonUserID:uid completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testSendPushToken {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Send push token call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_sendPushToken"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client sendPushToken:^(BOOL success) {
      XCTAssertFalse(success); // no push token on emulator
      [completionExpectation fulfill];
    }];
  }];

  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testScreens {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Screens call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_screens"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client automationWithID:self.noCodeScreenId completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue(res[@"success"]);
      XCTAssertTrue([self.noCodeScreenId isEqualToString:res[@"data"][@"id"]]);
      XCTAssertTrue([@"#CDFFD7" isEqualToString:res[@"data"][@"background"]]);
      XCTAssertTrue([@"EN" isEqualToString:res[@"data"][@"lang"]]);
      XCTAssertTrue([@"screen" isEqualToString:res[@"data"][@"object"]]);
      
      NSString *htmlBody = res[@"data"][@"body"];
      XCTAssertTrue([htmlBody length] > 0);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testScreensError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Screens error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_screens"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  // when
  [client automationWithID:self.noCodeScreenId completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testViews {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Views call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_views"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client trackScreenShownWithID:self.noCodeScreenId completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNil(res);
      XCTAssertNotNil(error);
      XCTAssertTrue([@"Could not find required related object" isEqualToString:[error localizedDescription]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testActionPoints {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Action points call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_actionPoints"];
  QNAPIClient *client = [self getClient:uid];
  
  NSDictionary *expRes = @{
    @"items": @[],
  };

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client userActionPointsWithCompletion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue([self areDictionariesDeepEqual:expRes second:res[@"data"]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testActionPointsError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Action points call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_actionPoints"];
  QNAPIClient *client = [self getClient:uid projectKey:kIncorrectProjectKey];
  
  // when
  [client userActionPointsWithCompletion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)assertProjectNotFoundError:(id)data error:(NSError *)error {
  XCTAssertNil(data);
  XCTAssertNotNil(error);
  XCTAssertEqual(error.code, 5);
  XCTAssertTrue([error.userInfo[NSDebugDescriptionErrorKey] isEqualToString:@"Internal error code: 10003."]);
  XCTAssertTrue([error.localizedDescription isEqualToString:@"Invalid access token received"]);
}

- (void)assertAccessDeniedError:(id)data error:(NSError *)error {
  XCTAssertNil(data);
  XCTAssertNotNil(error);
  XCTAssertEqual(error.code, 401);
  XCTAssertTrue([error.localizedDescription isEqualToString:@"Access denied"]);
}

- (BOOL)areArraysDeepEqual:(NSArray *)first second:(NSArray *)second {
  if (@available(iOS 13.0, *)) {
    NSOrderedCollectionDifference *diff = [first differenceFromArray:second
                                                         withOptions:0
                                                usingEquivalenceTest:^BOOL(id  _Nonnull obj1, id  _Nonnull obj2) {
      return [self areObjectsEqual:obj1 second:obj2];
    }];

    return ![diff hasChanges];
  } else {
    return [first isEqualToArray:second];
  }
}

- (BOOL)areDictionariesDeepEqual:(NSDictionary *)first second:(NSDictionary *)second {
  if (first.count != second.count) {
    return NO;
  }
  BOOL hasDiff = NO;
  for (NSString *key in first.allKeys) {
    id obj1 = first[key];
    id obj2 = second[key];

    hasDiff = ![self areObjectsEqual:obj1 second:obj2];

    if (hasDiff) {
      break;
    }
  }
  
  return !hasDiff;
}

- (BOOL)areObjectsEqual:(id  _Nonnull)obj1 second:(id  _Nonnull)obj2 {
  if ([obj1 isKindOfClass:[NSArray class]] && [obj2 isKindOfClass:[NSArray class]]) {
    return [self areArraysDeepEqual:obj1 second:obj2];
  }
  if ([obj1 isKindOfClass:[NSDictionary class]] && [obj2 isKindOfClass:[NSDictionary class]]) {
    return [self areDictionariesDeepEqual:obj1 second:obj2];
  }
  if ([obj1 isKindOfClass:[NSNumber class]] && [obj2 isKindOfClass:[NSNumber class]]) {
    return [obj1 isEqualToNumber:obj2];
  }
  if ([obj1 isKindOfClass:[NSString class]] && [obj2 isKindOfClass:[NSString class]]) {
    return [obj1 isEqualToString:obj2];
  }
  return obj1 == obj2;
}

- (QNAPIClient *)getClient:(NSString *)uid {
  return [self getClient:uid projectKey:kProjectKey];
}

- (QNAPIClient *)getClient:(NSString *)uid projectKey:(NSString *)projectKey {
  QNAPIClient *client = [[QNAPIClient alloc] init];

  [client setBaseURL:kAPIBase];
  [client setApiKey:projectKey];
  [client setSDKVersion:kSDKVersion];
  [client setUserID:uid];
  
  return client;
}

@end
