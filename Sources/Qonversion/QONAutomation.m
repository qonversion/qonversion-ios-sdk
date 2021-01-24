//
//  QONAutomation.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QONAutomation.h"
#import "QNAutomationsFlowCoordinator.h"

@interface QONAutomation ()

@property (nonatomic, weak) id<QONAutomationsDelegate> automationsDelegate;

@end

@implementation QONAutomation

+ (BOOL)handlePushNotification:(NSDictionary *)userInfo {
  return [[QNAutomationsFlowCoordinator sharedInstance] handlePushNotification:userInfo];
}

+ (void)setAutomationsDelegate:(id<QONAutomationsDelegate>)delegate {
  [[QNAutomationsFlowCoordinator sharedInstance] setAutomationsDelegate:delegate];
}

+ (void)showAutomationWithID:(NSString *)automationID {
  [[QNAutomationsFlowCoordinator sharedInstance] showAutomationWithID:automationID];
}

@end
