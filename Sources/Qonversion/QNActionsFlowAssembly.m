//
//  QNActionsFlowAssembly.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNActionsFlowAssembly.h"
#import "ActionsViewController.h"
#import "QNActionsHandler.h"
#import "QNActionsService.h"
#import "QNAPIClient.h"

@implementation QNActionsFlowAssembly

- (ActionsViewController *)configureActionsViewControllerWithActionID:(NSString *)actionID delegate:(id<ActionsViewControllerDelegate>)delegate {
  ActionsViewController *vc = [ActionsViewController new];
  vc.actionID = actionID;
  vc.delegate = delegate;
  
  QNActionsService *actionsService = [QNActionsService new];
  actionsService.apiClient = [QNAPIClient shared];
  
  vc.actionsHandler = [QNActionsHandler new];
  vc.actionsService = actionsService;
  vc.flowAssembly = [QNActionsFlowAssembly new];
  
  return vc;
}

@end
