//
//  QONAutomationsFlowAssembly.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS

#import "QONAutomationsFlowAssembly.h"
#import "QONAutomationsViewController.h"
#import "QONAutomationsActionsHandler.h"
#import "QONAutomationsService.h"
#import "QNAPIClient.h"
#import "QONAutomationsMapper.h"
#import "QONAutomationsScreen.h"
#import "QONAutomationsScreenProcessor.h"
#import "QONAutomationsEventsMapper.h"
#import "QONNotificationsService.h"

@implementation QONAutomationsFlowAssembly

- (QONAutomationsViewController *)configureAutomationsViewControllerWithScreen:(QONAutomationsScreen *)screen delegate:(id<QONAutomationsViewControllerDelegate> _Nullable)delegate {
  QONAutomationsViewController *vc = [QONAutomationsViewController new];
  vc.screen = screen;
  vc.delegate = delegate;
  
  vc.actionsHandler = [QONAutomationsActionsHandler new];
  vc.automationsService = [self automationsService];
  vc.flowAssembly = [QONAutomationsFlowAssembly new];
  vc.screenProcessor = [QONAutomationsScreenProcessor new];
  
  return vc;
}

- (QONAutomationsService *)automationsService {
  QONAutomationsService *automationsService = [QONAutomationsService new];
  automationsService.apiClient = [QNAPIClient shared];
  automationsService.mapper = [self screensMapper];
  
  return automationsService;
}

- (QONNotificationsService *)notificationsService {
  QONNotificationsService *notificationsService = [QONNotificationsService new];
  notificationsService.apiClient = [QNAPIClient shared];
  
  return notificationsService;
}

- (QONAutomationsMapper *)screensMapper {
  return [QONAutomationsMapper new];
}

- (QONAutomationsActionsHandler *)actionsHandler {
  return [QONAutomationsActionsHandler new];
}

- (QONAutomationsEventsMapper *)eventsMapper {
  return [QONAutomationsEventsMapper new];
}

@end
#endif
