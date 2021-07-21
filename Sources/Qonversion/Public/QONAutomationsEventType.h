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

  QONAutomationsEventTypeSubscriptionCancelled = 2
} NS_SWIFT_NAME(Qonversion.AutomationsEventType);
