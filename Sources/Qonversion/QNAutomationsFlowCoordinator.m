//
//  QNAutomationsFlowCoordinator.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNAutomationsFlowCoordinator.h"
#import "QNAutomationsFlowAssembly.h"
#import "QONAutomationsDelegate.h"
#import "QNAutomationsViewController.h"
#import "QNAutomationsService.h"
#import "QNAutomationScreen.h"
#import "QNActionsHandler.h"
#import "QNUserActionPoint.h"

@interface QNAutomationsFlowCoordinator() <QNAutomationsViewControllerDelegate>

@property (nonatomic, weak) id<QONAutomationsDelegate> automationsDelegate;
@property (nonatomic, strong) QNAutomationsFlowAssembly *assembly;
@property (nonatomic, strong) QNAutomationsService *automationsService;

@end

@implementation QNAutomationsFlowCoordinator

+ (instancetype)sharedInstance {
  static id shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [self new];
  });
  
  return shared;
}

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _assembly = [QNAutomationsFlowAssembly new];
    _automationsService = [_assembly automationService];
  }
  
  return self;
}

- (void)setAutomationsDelegate:(id<QONAutomationsDelegate>)automationsDelegate {
  _automationsDelegate = automationsDelegate;
}

- (BOOL)handlePushNotification:(NSDictionary *)userInfo {
  BOOL shouldShowAutomation = [userInfo[@"qonv.pick_screen"] boolValue];
  if (shouldShowAutomation) {
    [self showAutomationIfExists];
  }
  
  return shouldShowAutomation;
}

- (void)showAutomationIfExists {
  __block __weak QNAutomationsFlowCoordinator *weakSelf = self;
  [self.automationsService obtainAutomationScreensWithCompletion:^(NSArray<QNUserActionPoint *> *actionPoints, NSError * _Nullable error) {
    NSArray<QNUserActionPoint *> *sortedActions = [actionPoints sortedArrayUsingSelector:@selector(createDate)];
    QNUserActionPoint *latestAction = sortedActions.lastObject;
    NSString *automationID = latestAction.screenId;
    
    if (automationID.length > 0) {
      [weakSelf showAutomationWithID:automationID];
    }
  }];
}

- (void)showAutomationWithID:(NSString *)automationID {
  __block __weak QNAutomationsFlowCoordinator *weakSelf = self;
  [self.automationsService automationWithID:automationID completion:^(QNAutomationScreen *screen, NSError * _Nullable error) {
    if (screen) {
      [weakSelf.automationsService trackScreenShownWithID:automationID];
      QNAutomationsViewController *viewController = [weakSelf.assembly configureAutomationsViewControllerWithHtmlString:screen.htmlString delegate:self];
      
      UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
      navigationController.navigationBarHidden = YES;
      
      UIViewController *presentationViewController;
      
      if ([weakSelf.automationsDelegate respondsToSelector:@selector(controllerForNavigation)]) {
        presentationViewController = [weakSelf.automationsDelegate controllerForNavigation];
      } else {
        presentationViewController = [weakSelf topLevelViewController];
      }
      navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
      [presentationViewController presentViewController:navigationController animated:YES completion:nil];
    }
  }];
}

- (void)automationsViewController:(QNAutomationsViewController *)viewController didFinishAction:(QONAction *)action {
  if ([self.automationsDelegate respondsToSelector:@selector(automationFlowFinishedWithAction:)]) {
    [self.automationsDelegate automationFlowFinishedWithAction:action];
  }
}

#pragma mark - Priate

- (UIViewController *)topLevelViewController {
  UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;

  while (topController.presentedViewController) {
    topController = topController.presentedViewController;
  }

  return topController;
}

@end
