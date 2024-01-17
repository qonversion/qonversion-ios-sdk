//
//  QNAPIClientIntegrationTests.m
//  IntegrationTests
//
//  Created by Kamo Spertsyan on 29.03.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "QNAPIClient.h"
#import "QNAPIConstants.h"
#import "QNProperties.h"
#import "QNIntegrationTestConstants.h"
#import "XCTestCase+IntegrationTestJSON.h"
#import "XCTestCase+IntegrationTestsHelpers.h"

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

@property (nonatomic, copy) NSString *kSDKVersion;
@property (nonatomic, copy) NSString *kProjectKey;
@property (nonatomic, copy) NSString *kIncorrectProjectKey;
@property (nonatomic, assign) const int kRequestTimeout;

@end

@implementation QNAPIClientIntegrationTests

- (void)setUp {
  self.kSDKVersion = @"10.11.12";
  self.kProjectKey = @"V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-a";
  self.kRequestTimeout = 10;
  self.kIncorrectProjectKey = @"V4pK6FQo3PiDPj_2vYO1qZpNBbFXNP-aaaa";

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
  
  
  self.expectedPermissions = [self JSONObjectFromContentsOfFile:keyQNExpectedEntitlementsJSON];
  
  self.mainRequestData = [self  dictionaryFromContentsOfFile:keyQNInitRequestMainDataJSON];

  NSMutableDictionary *requestData = [self.mainRequestData mutableCopy];
  requestData[@"purchase"] = @{
    @"country": @"USA",
    @"currency": @"USD",
    @"original_transaction_id": @"",
    @"period_number_of_units": @"1",
    @"period_unit": @"2",
    @"product": @"apple_monthly",
    @"product_id": @"test_monthly",
    @"transaction_id": @"2000000305530406",
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testInitError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Init error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_init"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];

  // when
  [client launchRequest:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testPurchaseError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Purchase error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_purchase"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];
  
  // when
  [client purchaseRequestWith:self.purchaseData completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testAttributionError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Attribution error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_attribution"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];
  
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testSendProperties {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Send properties call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_send_properties"];
  QNAPIClient *client = [self getClient:uid];

  NSDictionary *data = @{
          @"customProperty": @"custom property value",
          [QNProperties keyForProperty:QONUserPropertyKeyUserID]: @"custom user id",
  };
  
  NSArray *expSavedProperties = @[
    @{
      @"key": @"customProperty",
      @"value": @"custom property value"
    },
    @{
      @"key": @"_q_custom_user_id",
      @"value": @"custom user id"
    }
  ];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
      XCTAssertNil(createUserError);

      [client sendProperties:data completion:^(NSDictionary *_Nullable res, NSError *_Nullable error) {
          XCTAssertNotNil(res);
          XCTAssertNil(error);
          XCTAssertTrue([self areArraysDeepEqual:res[@"propertyErrors"] second:@[]]);
          XCTAssertTrue([self areArraysOfDictionariesEqual:res[@"savedProperties"] second:expSavedProperties descriptor:@"key"]);
          [completionExpectation fulfill];
      }];
  }];

  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testSendPropertiesError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Send properties error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_send_properties"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];
  
  NSDictionary *data = @{
    @"customProperty": @"custom property value",
    [QNProperties keyForProperty:QONUserPropertyKeyUserID]: @"custom user id",
  };

  // when
  [client sendProperties:data completion:^(NSDictionary *_Nullable res, NSError *_Nullable error) {
      [self assertAccessDeniedError:res error:error];
      [completionExpectation fulfill];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testGetProperties {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Get properties call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_get_properties"];
  QNAPIClient *client = [self getClient:uid];

  NSDictionary *data = @{
          @"customProperty": @"custom property value",
          [QNProperties keyForProperty:QONUserPropertyKeyUserID]: @"custom user id",
  };

  NSArray *expRes = @[
    @{
      @"key": @"customProperty",
      @"value": @"custom property value"
    },
    @{
      @"key": @"_q_custom_user_id",
      @"value": @"custom user id"
    }
  ];

  // when
  [client launchRequest:^(NSDictionary * _Nullable initRes, NSError * _Nullable createUserError) {
      XCTAssertNil(createUserError);

      [client sendProperties:data completion:^(NSDictionary *_Nullable sendPropertiesRes, NSError *_Nullable sendPropertiesError) {
          XCTAssertNil(sendPropertiesError);

          [client getProperties:^(NSArray *res, NSError *error) {
              XCTAssertNil(error);
              XCTAssertTrue([self areArraysOfDictionariesEqual:res second:expRes descriptor:@"key"]);
              [completionExpectation fulfill];
          }];
      }];
  }];

  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testGetPropertiesError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Get properties error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_get_properties"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];

  // when
  [client getProperties:^(NSArray *_Nullable res, NSError *_Nullable error) {
      [self assertAccessDeniedError:res error:error];
      [completionExpectation fulfill];
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testCheckTrialIntroEligibilityError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"CheckTrialIntroEligibility error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_checkTrialIntroEligibility"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];
  
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

- (void)testIdentifyError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Identify error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_identify"];
  NSString *identityId = [NSString stringWithFormat:@"%@%@", @"identity_for_", uid];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];
  
  // when
  [client createIdentityForUserID:identityId anonUserID:uid completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
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
      XCTAssertFalse(success); // no push token on emulator
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
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
}

- (void)testScreensError {
  // given
  XCTestExpectation *completionExpectation = [self expectationWithDescription:@"Screens error call"];
  NSString *uid = [NSString stringWithFormat:@"%@%@", self.kUidPrefix, @"_screens"];
  QNAPIClient *client = [self getClient:uid projectKey:self.kIncorrectProjectKey];
  
  // when
  [client automationWithID:self.noCodeScreenId completion:^(NSDictionary * _Nullable res, NSError * _Nullable error) {
    [self assertAccessDeniedError:res error:error];
    [completionExpectation fulfill];
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
      XCTAssertNil(res);
      XCTAssertNotNil(error);
      XCTAssertTrue([@"Could not find required related object" isEqualToString:[error localizedDescription]]);
      [completionExpectation fulfill];
    }];
  }];
  
  // then
  [self waitForExpectationsWithTimeout:self.kRequestTimeout handler:nil];
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

- (QNAPIClient *)getClient:(NSString *)uid {
  return [self getClient:uid projectKey:self.kProjectKey];
}

- (QNAPIClient *)getClient:(NSString *)uid projectKey:(NSString *)projectKey {
  QNAPIClient *client = [[QNAPIClient alloc] init];

  [client setBaseURL:kAPIBase];
  [client setApiKey:projectKey];
  [client setSDKVersion:self.kSDKVersion];
  [client setUserID:uid];
  
  return client;
}

@end
