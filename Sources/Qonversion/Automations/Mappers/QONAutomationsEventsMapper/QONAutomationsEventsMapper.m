//
//  QONAutomationsEventsMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsEventsMapper.h"
#import "QONAutomationsEvent+Protected.h"
#import "QNUtils.h"

@interface QONAutomationsEventsMapper ()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *eventsMap;

@end

@implementation QONAutomationsEventsMapper

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _eventsMap = @{
      @"trial_started": @(QONAutomationsEventTypeTrialStarted),
      @"trial_converted": @(QONAutomationsEventTypeTrialConverted),
      @"trial_canceled": @(QONAutomationsEventTypeTrialCanceled),
      @"trial_billing_retry": @(QONAutomationsEventTypeTrialBillingRetry),
      @"subscription_started": @(QONAutomationsEventTypeSubscriptionStarted),
      @"subscription_renewed": @(QONAutomationsEventTypeSubscriptionRenewed),
      @"subscription_refunded": @(QONAutomationsEventTypeSubscriptionRefunded),
      @"subscription_canceled": @(QONAutomationsEventTypeSubscriptionCanceled),
      @"subscription_billing_retry": @(QONAutomationsEventTypeSubscriptionBillingRetry),
      @"inapp_purchase": @(QONAutomationsEventTypeInAppPurchase),
      @"subscription_upgraded": @(QONAutomationsEventTypeSubscriptionUpgraded),
      @"trial_still_active": @(QONAutomationsEventTypeTrialStillActive)
    };
  }
  
  return self;
}

- (QONAutomationsEvent * _Nullable)eventFromNotification:(NSDictionary<NSString *, id> *)notificationInfo {
  NSDictionary *eventInfo = notificationInfo[@"qonv.event"];
  
  if (![eventInfo isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  NSNumber *happened = notificationInfo[@"happened"];
  NSDate *date = [QNUtils dateFromTimestamp:happened];
  if (!date) {
    date = [NSDate date];
  }
  
  NSString *eventName = notificationInfo[@"name"];
  QONAutomationsEventType eventType = self.eventsMap[eventName].integerValue;
  
  QONAutomationsEvent *event = [[QONAutomationsEvent alloc] initWithType:eventType date:date];
  
  return event;
}

@end
