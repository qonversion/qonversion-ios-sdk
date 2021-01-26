//
//  QONAutomationsFlowAssembly.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsFlowAssembly.h"
#import "QONAutomationsViewController.h"
#import "QONAutomationsActionsHandler.h"
#import "QONAutomationsService.h"
#import "QNAPIClient.h"
#import "QONAutomationsMapper.h"

@implementation QONAutomationsFlowAssembly

- (QONAutomationsViewController *)configureAutomationsViewControllerWithHtmlString:(NSString *)htmlString delegate:(id<QNAutomationsViewControllerDelegate> _Nullable)delegate {
  QONAutomationsViewController *vc = [QONAutomationsViewController new];
  vc.htmlString = htmlString;
  vc.delegate = delegate;
  
  vc.actionsHandler = [QONAutomationsActionsHandler new];
  vc.automationsService = [self automationsService];
  vc.flowAssembly = [QONAutomationsFlowAssembly new];
  
  return vc;
}

- (QONAutomationsService *)automationsService {
  QONAutomationsService *automationsService = [QONAutomationsService new];
  automationsService.apiClient = [QNAPIClient shared];
  automationsService.mapper = [self screensMapper];
  
  return automationsService;
}

- (QONAutomationsMapper *)screensMapper {
  return [QONAutomationsMapper new];
}

- (QONAutomationsActionsHandler *)actionsHandler {
  return [QONAutomationsActionsHandler new];
}

@end
