//
//  QONAutomationsEventsMapperTests.m
//  QonversionTests
//
//  Created by Surik Sarkisyan on 26.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "XCTestCase+Unmock.h"
#import "QONAutomationsEventsMapper.h"
#import "QNUserInfoService.h"

@interface QONAutomationsEventsMapperTests : XCTestCase

@property (nonatomic, strong) QONAutomationsEventsMapper *mapper;

@end

@implementation QONAutomationsEventsMapperTests

- (void)setUp {
  self.mapper = [QONAutomationsEventsMapper new];
}

- (void)tearDown {
  self.mapper = nil;
}

- (void)testEventFromNotification_noEvent {
  // given
  NSDictionary *emptyDict = @{};
  
  // when
  QONAutomationsEvent *event = [self.mapper eventFromNotification:emptyDict];
  
  // then
  XCTAssertNil(event);
}

- (void)testEventFromNotification_emptyName {
  // given
  NSDictionary *dict = @{@"qonv.event" : @{}};
  
  // when
  QONAutomationsEvent *event = [self.mapper eventFromNotification:dict];
  
  // then
  XCTAssertNil(event);
}

- (void)testEventFromNotification_nullName {
  // given
  NSDictionary *dict = @{@"qonv.event" : @{@"name": [NSNull null]}};
  
  // when
  QONAutomationsEvent *event = [self.mapper eventFromNotification:dict];
  
  // then
  XCTAssertNil(event);
}

- (void)testEventFromNotification_emptyType {
  // given
  NSDictionary *dict = @{@"qonv.event" : @{@"name": @"someRandomName"}};
  
  // when
  QONAutomationsEvent *event = [self.mapper eventFromNotification:dict];
  
  // then
  XCTAssertNil(event);
}

- (void)testEventFromNotification_notEmptyType {
  NSDictionary *eventsDict = @{
    @"trial_started": @(QONAutomationsEventTypeTrialStarted),
    @"trial_converted": @(QONAutomationsEventTypeTrialConverted),
    @"trial_canceled": @(QONAutomationsEventTypeTrialCanceled),
    @"trial_billing_retry_entered": @(QONAutomationsEventTypeTrialBillingRetry),
    @"subscription_started": @(QONAutomationsEventTypeSubscriptionStarted),
    @"subscription_renewed": @(QONAutomationsEventTypeSubscriptionRenewed),
    @"subscription_refunded": @(QONAutomationsEventTypeSubscriptionRefunded),
    @"subscription_canceled": @(QONAutomationsEventTypeSubscriptionCanceled),
    @"subscription_billing_retry_entered": @(QONAutomationsEventTypeSubscriptionBillingRetry),
    @"in_app_purchase": @(QONAutomationsEventTypeInAppPurchase),
    @"subscription_upgraded": @(QONAutomationsEventTypeSubscriptionUpgraded),
    @"trial_still_active": @(QONAutomationsEventTypeTrialStillActive),
    @"trial_expired" : @(QONAutomationsEventTypeTrialExpired),
    @"subscription_expired": @(QONAutomationsEventTypeSubscriptionExpired),
    @"subscription_downgraded": @(QONAutomationsEventTypeSubscriptionDowngraded),
    @"subscription_product_changed": @(QONAutomationsEventTypeSubscriptionProductChanged)
  };
  
  for (NSString *key in eventsDict.allKeys) {
    // given
    NSString *eventName = key;
    NSDictionary *dict = @{@"qonv.event" : @{@"name": eventName}};
    
    // when
    QONAutomationsEvent *event = [self.mapper eventFromNotification:dict];
    
    // then
    XCTAssertNotNil(event);
    XCTAssertEqual([eventsDict[key] integerValue], event.type);
  }
}

- (void)testEventFromNotification_dateMappedForEmptyDate {
  // given
  NSDate *currentDate = [NSDate date];
  NSDictionary *dict = @{@"qonv.event" : @{@"name": @"trial_started"}};
  id dateMock = OCMClassMock([NSDate class]);
  OCMStub([dateMock date]).andReturn(currentDate);
  
  // when
  QONAutomationsEvent *event = [self.mapper eventFromNotification:dict];
  
  // then
  XCTAssertNotNil(event);
  XCTAssertTrue([event.date isEqualToDate:currentDate]);
  
  [self unmock:dateMock];
}

@end
