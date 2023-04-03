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

NSString *const kSDKVersion = @"10.11.12";
NSString *const kProjectKey = @"V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-a";
const int kRequestTimeout = 10;

@interface QNAPIClientIntegrationTests : XCTestCase

@property (nonatomic) NSString *kUidPrefix;
@property (nonatomic) NSDictionary *monthlyProduct;
@property (nonatomic) NSDictionary *annualProduct;
@property (nonatomic) NSDictionary *inappProduct;
@property (nonatomic) NSDictionary *expectedOffering;
@property (nonatomic) NSDictionary *expectedProductPermissions;
@property (nonatomic) NSArray *expectedProducts;
@property (nonatomic) NSArray *expectedOfferings;
@property (nonatomic) NSArray *expectedPermissions;
@property (nonatomic) NSDictionary *mainRequestData;
@property (nonatomic) NSDictionary *purchaseData;
@property (nonatomic) NSString *noCodeScreenId;

@end

@implementation QNAPIClientIntegrationTests

- (void)setUp {
  NSString *const timestamp = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
  _kUidPrefix = [NSString stringWithFormat:@"%@%@", @"QON_test_uid_ios_", timestamp];

  _monthlyProduct = @{
    @"duration": @1,
    @"id": @"test_monthly",
    @"store_id": @"apple_monthly",
    @"type": @1,
  };
  
  _annualProduct = @{
    @"duration": @4,
    @"id": @"test_annual",
    @"store_id": @"apple_annual",
    @"type": @0,
  };
  
  _inappProduct = @{
    @"duration": [NSNull null],
    @"id": @"test_inapp",
    @"store_id": @"apple_inapp",
    @"type": @2,
  };
  
  _expectedProducts = @[_monthlyProduct, _annualProduct, _inappProduct];
  
  _expectedOffering = @{
    @"id": @"main",
    @"products": @[_annualProduct, _monthlyProduct],
    @"tag": @1,
  };
  
  _expectedOfferings = @[_expectedOffering];
  
  _expectedProductPermissions = @{
    _annualProduct[@"id"]: @[@"premium"],
    _monthlyProduct[@"id"]: @[@"premium"],
    _inappProduct[@"id"]: @[@"noAds"],
  };
  
  _expectedPermissions = @[
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
  
  _mainRequestData = @{
      @"custom_uid": @"",
      @"device": @{
        @"app_version": @"1.0.0",
        @"carrier": @"Beeline",
        @"country": @"Sint Maarten",
        @"device_id": @"26A85FA5-2B19-4DBA-B30B-94B13457382B",
        @"locale": @"Russian",
        @"manufacturer": @"Apple",
        @"model": @"iPhone14,3",
        @"os": @"iOS",
        @"os_version": @"16.3.1",
        @"timezone": @"Europe/Moscow",
        @"tracking_enabled": @1,
      },
      @"install_date": @1680246666,
      @"receipt": @"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",
  };

  NSMutableDictionary *requestData = [_mainRequestData mutableCopy];
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

  _purchaseData = requestData;
  
  _noCodeScreenId = @"lsarjYcU";
}

- (void)testInit {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Init call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_init"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    XCTAssertNotNil(res);
    XCTAssertNil(error);
    XCTAssertTrue(res[@"success"]);
    XCTAssertTrue([uid isEqualToString:res[@"data"][@"uid"]]);
    XCTAssertTrue([self areArraysDeepEqual:self->_expectedProducts second:res[@"data"][@"products"]]);
    XCTAssertTrue([self areArraysDeepEqual:self->_expectedOfferings second:res[@"data"][@"offerings"]]);
    XCTAssertTrue([self areArraysDeepEqual:@[] second:res[@"data"][@"permissions"]]);
    XCTAssertTrue([self areDictionariesDeepEqual:self->_expectedProductPermissions second:res[@"data"][@"products_permissions"]]);
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testPurchase {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Purchase call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_purchase"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client purchaseRequestWith:self->_purchaseData completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue(res[@"success"]);
      XCTAssertTrue([uid isEqualToString:res[@"data"][@"uid"]]);
      XCTAssertTrue([self areArraysDeepEqual:self->_expectedProducts second:res[@"data"][@"products"]]);
      XCTAssertTrue([self areArraysDeepEqual:self->_expectedOfferings second:res[@"data"][@"offerings"]]);
      XCTAssertTrue([self areArraysDeepEqual:self->_expectedPermissions second:res[@"data"][@"permissions"]]);
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
  [client purchaseRequestWith:self->_purchaseData completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    XCTAssertNotNil(res);
    XCTAssertNil(error);
    XCTAssertTrue(res[@"success"]);
    XCTAssertTrue([uid isEqualToString:res[@"data"][@"uid"]]);
    XCTAssertTrue([self areArraysDeepEqual:self->_expectedProducts second:res[@"data"][@"products"]]);
    XCTAssertTrue([self areArraysDeepEqual:self->_expectedOfferings second:res[@"data"][@"offerings"]]);
    XCTAssertTrue([self areArraysDeepEqual:self->_expectedPermissions second:res[@"data"][@"permissions"]]);
    XCTAssertTrue([self areDictionariesDeepEqual:@{} second:res[@"data"][@"products_permissions"]]);
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:kRequestTimeout handler:nil];
}

- (void)testAttribution {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Attribution call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_attribution"];
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

- (void)testProperties {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Properties call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_properties"];
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

- (void)testCheckTrialIntroEligibility {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"CheckTrialIntroEligibility call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_checkTrialIntroEligibility"];
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

- (void)testIdentify {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Identify call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_identify"];
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

- (void)testSendPushToken {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Send push token call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_sendPushToken"];
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
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_screens"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client automationWithID:self->_noCodeScreenId completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      XCTAssertNotNil(res);
      XCTAssertNil(error);
      XCTAssertTrue(res[@"success"]);
      XCTAssertTrue([self->_noCodeScreenId isEqualToString:res[@"data"][@"id"]]);
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

- (void)testViews {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Views call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_views"];
  QNAPIClient *client = [self getClient:uid];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client trackScreenShownWithID:self->_noCodeScreenId completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
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
  NSString *uid = [NSString stringWithFormat:@"%@%@", _kUidPrefix, @"_actionPoints"];
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
  QNAPIClient *client = [[QNAPIClient alloc] init];

  [client setBaseURL:kAPIBase];
  [client setApiKey:kProjectKey];
  [client setSDKVersion:kSDKVersion];
  [client setUserID:uid];
  
  return client;
}

@end
