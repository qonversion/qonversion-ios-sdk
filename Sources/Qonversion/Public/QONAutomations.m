//
//  QONAutomations.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.01.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS
#import "QONAutomations.h"
#import "QONAutomationsFlowCoordinator.h"
#import "QNInternalConstants.h"

@interface QONAutomations ()

@property (nonatomic, weak) id<QONAutomationsDelegate> automationsDelegate;

@end

@implementation QONAutomations

+ (instancetype)sharedInstance {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [QONAutomations new];
    [[NSNotificationCenter defaultCenter] addObserver:shared selector:@selector(didFinishLaunch) name:kLaunchIsFinishedNotification object:nil];
  });
  
  return shared;
}

- (void)didFinishLaunch {
  [[QONAutomationsFlowCoordinator sharedInstance] didFinishLaunch];
}

- (void)setDelegate:(id<QONAutomationsDelegate>)delegate {
  [[QONAutomationsFlowCoordinator sharedInstance] setAutomationsDelegate:delegate];
}

- (void)showScreenWithID:(NSString *)screenID completion:(nullable QONShowScreenCompletionHandler)completion {
  [[QONAutomationsFlowCoordinator sharedInstance] showAutomationWithID:screenID completion:completion];
}

- (void)setNotificationsToken:(NSData *)token {
  [[QONAutomationsFlowCoordinator sharedInstance] sendPushToken:token];
}

- (BOOL)handleNotification:(NSDictionary *)userInfo {
  return [[QONAutomationsFlowCoordinator sharedInstance] handlePushNotification:userInfo];
}

- (NSDictionary *_Nullable)getNotificationCustomPayload:(NSDictionary *)userInfo {
  NSDictionary *customPayload = userInfo[kKeyNotificationsCustomPayload];
  if (![customPayload isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  
  return customPayload;
}

@end

#endif
