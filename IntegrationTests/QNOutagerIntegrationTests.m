//
//  QNOutagerIntegrationTests.m
//  IntegrationTests
//
//  Created by Kamo Spertsyan on 10.04.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "QNAPIClient.h"
#import "QNProperties.h"
#import "QNTestConstants.h"
#import "Helpers/XCTestCase+TestJSON.h"
#import "Helpers/XCTestCase+Helpers.h"


@interface QNOutagerIntegrationTests : XCTestCase

@property (nonatomic, copy) NSString *kUidPrefix;
@property (nonatomic, copy) NSDictionary *monthlyProduct;
@property (nonatomic, copy) NSDictionary *annualProduct;
@property (nonatomic, copy) NSDictionary *inappProduct;
@property (nonatomic, copy) NSDictionary *expectedOffering;
@property (nonatomic, copy) NSDictionary *expectedProductPermissions;
@property (nonatomic, copy) NSArray *expectedProducts;
@property (nonatomic, copy) NSArray *expectedOfferings;
@property (nonatomic, copy) NSDictionary *mainRequestData;
@property (nonatomic, copy) NSDictionary *purchaseData;
@property (nonatomic, copy) NSString *noCodeScreenId;

@property (nonatomic, copy) NSString *const kSDKVersion;
@property (nonatomic, copy) NSString *const kProjectKey;
@property (nonatomic) const int kRequestTimeout;

@end

@implementation QNOutagerIntegrationTests

- (void)setUp {
  self.kSDKVersion = @"10.11.12";
  self.kProjectKey = @"V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-a";
  self.kRequestTimeout = 10;

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
  
  self.expectedProducts = @[self.annualProduct, self.inappProduct, self.monthlyProduct];
  
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
  [self waitForExpectationsWithTimeout:self.self.kRequestTimeout handler:nil];
}

- (void)testPurchase {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Purchase call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_purchase"];
  QNAPIClient *client = [self getClient:uid];
  NSNumber *requestStartTimestamp = [NSNumber numberWithDouble: [[NSDate date] timeIntervalSince1970]];
  NSMutableDictionary *expectedPermission = [@{
    @"active": @1,
    @"associated_product": @"test_monthly",
    @"id": @"premium",
    @"renew_state": @0,
    @"source": @"unknown",
  } mutableCopy];

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

      XCTAssertTrue([res[@"data"][@"permissions"] count] == 1);

      // As we don't send purchase time with the purchase, then outager gets handler timestamp as started_timestamp for the result permission.
      // We check here, that that timestamp is between request started and ended timestamps.
      NSNumber *requestEndTimestamp = [NSNumber numberWithDouble: [[NSDate date] timeIntervalSince1970]];
      long resStartedTimestamp = [res[@"data"][@"permissions"][0][@"started_timestamp"] longValue];
      long resExpirationTimestamp = [res[@"data"][@"permissions"][0][@"expiration_timestamp"] longValue];
      long month = 30 * 24 * 60 * 60;
      XCTAssertTrue(resStartedTimestamp >= [requestStartTimestamp longValue]);
      XCTAssertTrue(resStartedTimestamp <= [requestEndTimestamp longValue]);
      XCTAssertTrue(resExpirationTimestamp == resStartedTimestamp + month);

      expectedPermission[@"started_timestamp"] = res[@"data"][@"permissions"][0][@"started_timestamp"];
      expectedPermission[@"expiration_timestamp"] = res[@"data"][@"permissions"][0][@"expiration_timestamp"];
      XCTAssertTrue([self areArraysDeepEqual:@[expectedPermission] second:res[@"data"][@"permissions"]]);

      XCTAssertTrue([self areDictionariesDeepEqual:self.expectedProductPermissions second:res[@"data"][@"products_permissions"]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
    @"data": @{},
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client checkTrialIntroEligibilityParamsForData:data completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      [self assertInternalServerError:res error:error];
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
      XCTAssertFalse(success);
      [completionExpectation fulfill];
    }];
  }];

  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
      [self assertInternalServerError:res error:error];
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
      [self assertInternalServerError:res error:error];
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testActionPoints {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Action points call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_actionPoints"];
  QNAPIClient *client = [self getClient:uid];
  
  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
    XCTAssertNil(createUserError);

    [client userActionPointsWithCompletion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
      [self assertInternalServerError:res error:error];
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)assertInternalServerError:(id)data error:(NSError *)error {
  XCTAssertNil(data);
  XCTAssertNotNil(error);
  XCTAssertEqual(error.code, 503);
  XCTAssertTrue([error.localizedDescription isEqualToString:@"Internal server error"]);
}

- (QNAPIClient *)getClient:(NSString *)uid {
  return [self getClient:uid projectKey:self.kProjectKey];
}

- (QNAPIClient *)getClient:(NSString *)uid projectKey:(NSString *)projectKey {
  QNAPIClient *client = [[QNAPIClient alloc] init];

  [client setBaseURL:@"<paste outager link here>"];
  [client setApiKey:projectKey];
  [client setSDKVersion:self.kSDKVersion];
  [client setUserID:uid];
  
  return client;
}

@end
