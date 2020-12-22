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

@implementation QNAutomationsFlowAssembly

- (QNAutomationsViewController *)configureAutomationsViewControllerWithID:(NSString *)automationID delegate:(id<QNAutomationsViewControllerDelegate>)delegate {
  QNAutomationsViewController *vc = [QNAutomationsViewController new];
  vc.automationID = automationID;
  vc.delegate = delegate;
  
  QNAutomationsService *automationsService = [QNAutomationsService new];
  automationsService.apiClient = [QNAPIClient shared];
  
  vc.actionsHandler = [QNActionsHandler new];
  vc.automationsService = automationsService;
  vc.flowAssembly = [QNAutomationsFlowAssembly new];
  
  return vc;
}

@end
