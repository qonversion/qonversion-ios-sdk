//
//  ActionsFlowCoordinator.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "ActionsFlowCoordinator.h"
#import "QNActionsFlowAssembly.h"
#import "ActionsDelegate.h"
#import "ActionsViewController.h"

@interface ActionsFlowCoordinator() <ActionsViewControllerDelegate>

@property (nonatomic, weak) id<ActionsDelegate> actionsDelegate;
@property (nonatomic, strong) QNActionsFlowAssembly *assembly;

@end

@implementation ActionsFlowCoordinator

+ (instancetype)sharedInstance {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = self.new;
  });
  
  return shared;
}

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _assembly = [QNActionsFlowAssembly new];
  }
  
  return self;
}

- (void)setActionsDelegate:(id<ActionsDelegate>)actionsDelegate {
  _actionsDelegate = actionsDelegate;
}

- (void)showActionWithID:(NSString *)actionID {
  self.actionsDelegate = nil;
  if ([self.actionsDelegate canShowActionWithID:actionID]) {
    ActionsViewController *viewController = [self.assembly configureActionsViewControllerWithActionID:actionID delegate:self];
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;
    
    UIViewController *presentationViewController = [self.actionsDelegate controllerForNavigation];
    
    if (!presentationViewController) {
      presentationViewController = [self topLevelViewController];
    }
    
    [presentationViewController presentViewController:navigationController animated:YES completion:nil];
  }
}

- (void)actionViewController:(ActionsViewController *)viewController didFinishAction:(QNAction *)action {
  [self.actionsDelegate actionFlowFinished];
}

#pragma mark - Priate

- (UIViewController *)topLevelViewController {
  return nil;
}

@end
