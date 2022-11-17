//
//  QONNotificationsService.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 15.11.2022.
//  Copyright © 2022 Qonversion Inc. All rights reserved.
//

#import "QONNotificationsService.h"
#import "QNDevice.h"

@implementation QONNotificationsService

- (void)sendPushToken {
  [self.apiClient sendPushToken:^(BOOL success) {
    if (success) {
      [[QNDevice current] setPushTokenProcessed:YES];
    }
  }];
}

@end
