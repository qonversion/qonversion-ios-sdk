//
//  QONAutomationsEventType.h
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

typedef NS_ENUM(NSInteger, QONAutomationsEventType) {
  QONAutomationsEventTypeUnknown = 0,
  QONAutomationsEventTypeTrialStarted = 1,
  QONAutomationsEventTypeTrialConverted = 2,
  QONAutomationsEventTypeTrialCanceled = 3,
  QONAutomationsEventTypeTrialBillingRetry = 4,
  QONAutomationsEventTypeSubscriptionStarted = 5,
  QONAutomationsEventTypeSubscriptionRenewed = 6,
  QONAutomationsEventTypeSubscriptionRefunded = 7,
  QONAutomationsEventTypeSubscriptionCanceled = 8,
  QONAutomationsEventTypeSubscriptionBillingRetry = 9,
  QONAutomationsEventTypeInAppPurchase = 10,
  QONAutomationsEventTypeSubscriptionUpgraded = 11,
  QONAutomationsEventTypeTrialStillActive = 12,
  QONAutomationsEventTypeTrialExpired = 13,
  QONAutomationsEventTypeSubscriptionExpired = 14,
  QONAutomationsEventTypeSubscriptionDowngraded = 15,
  QONAutomationsEventTypeSubscriptionProductChanged = 16
} NS_SWIFT_NAME(Qonversion.AutomationsEventType);
