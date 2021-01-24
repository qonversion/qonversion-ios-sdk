//
//  QNAutomationsFlowAssembly.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNAutomationsFlowAssembly.h"
#import "QNAutomationsViewController.h"
#import "QNActionsHandler.h"
#import "QNAutomationsService.h"
#import "QNAPIClient.h"
#import "QNAutomationsMapper.h"

@implementation QNAutomationsFlowAssembly

- (QNAutomationsViewController *)configureAutomationsViewControllerWithHtmlString:(NSString *)htmlString delegate:(id<QNAutomationsViewControllerDelegate> _Nullable)delegate {
  QNAutomationsViewController *vc = [QNAutomationsViewController new];
  vc.htmlString = htmlString;
  vc.delegate = delegate;
  
  vc.actionsHandler = [QNActionsHandler new];
  vc.automationsService = [self automationService];
  vc.flowAssembly = [QNAutomationsFlowAssembly new];
  
  return vc;
}

- (QNAutomationsService *)automationService {
  QNAutomationsService *automationsService = [QNAutomationsService new];
  automationsService.apiClient = [QNAPIClient shared];
  automationsService.mapper = [self screensMapper];
  
  return automationsService;
}

- (QNAutomationsMapper *)screensMapper {
  return [QNAutomationsMapper new];
}

- (QNActionsHandler *)actionsHandler {
  return [QNActionsHandler new];
}

@end
