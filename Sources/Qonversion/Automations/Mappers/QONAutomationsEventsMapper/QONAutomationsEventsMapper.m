//
//  QONAutomationsEventsMapper.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 21.07.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsEventsMapper.h"

@implementation QONAutomationsEventsMapper

- (QONAutomationsEventType)eventTypeFromNotification:(NSDictionary<NSString *, id> *)notificationInfo {
  return QONAutomationsEventTypeTrialStarted;
}

@end
