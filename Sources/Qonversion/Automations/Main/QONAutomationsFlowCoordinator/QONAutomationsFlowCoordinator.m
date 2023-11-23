//
//  QONAutomationsFlowCoordinator.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS

#import "QONAutomationsFlowCoordinator.h"
#import "QONAutomationsFlowAssembly.h"
#import "QONAutomationsDelegate.h"
#import "QONAutomationsViewController.h"
#import "QONAutomationsService.h"
#import "QONAutomationsScreen.h"
#import "QONAutomationsActionsHandler.h"
#import "QONUserActionPoint.h"
#import "QONAutomations.h"
#import "QNUtils.h"
#import "QONAutomationsEvent.h"
#import "QONAutomationsEventsMapper.h"
#import "QNInternalConstants.h"
#import "QNDevice.h"
#import "QONNotificationsService.h"
#import "QONScreenCustomizationDelegate.h"
#import "QONAutomationsNavigationController.h"

@interface QONAutomationsFlowCoordinator() <QONAutomationsViewControllerDelegate>

@property (nonatomic, weak) id<QONAutomationsDelegate> automationsDelegate;
@property (nonatomic, weak) id<QONScreenCustomizationDelegate> screenCustomizationDelegate;
@property (nonatomic, strong) QONAutomationsFlowAssembly *assembly;
@property (nonatomic, strong) QONAutomationsService *automationsService;
@property (nonatomic, strong) QONAutomationsEventsMapper *eventsMapper;
@property (nonatomic, strong) QONNotificationsService *notificationsService;
@property (nonatomic, assign) BOOL isSDKLaunched;

@end

@implementation QONAutomationsFlowCoordinator

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
    _assembly = [QONAutomationsFlowAssembly new];
    _automationsService = [_assembly automationsService];
    _eventsMapper = [_assembly eventsMapper];
    _notificationsService = [_assembly notificationsService];
  }
  
  return self;
}

- (void)didFinishLaunch {
  self.isSDKLaunched = YES;
  
  [self processPushTokenRequest];
}

- (void)setAutomationsDelegate:(id<QONAutomationsDelegate>)automationsDelegate {
  _automationsDelegate = automationsDelegate;
}

- (void)setScreenCustomizationDelegate:(id<QONScreenCustomizationDelegate>)screenCustomizationDelegate {
  _screenCustomizationDelegate = screenCustomizationDelegate;
}

- (BOOL)handlePushNotification:(NSDictionary *)userInfo {
  BOOL shouldShowAutomation = [userInfo[@"qonv.pick_screen"] boolValue];
  if (shouldShowAutomation) {
    [self handleEvent:userInfo];
  }
  
  return shouldShowAutomation;
}

- (void)handleEvent:(NSDictionary *)userInfo {
  dispatch_async(dispatch_get_main_queue(), ^{
    QONAutomationsEvent *event = [self.eventsMapper eventFromNotification:userInfo];
    
    BOOL shouldHandle = YES;
    if (self.automationsDelegate && [self.automationsDelegate respondsToSelector:@selector(shouldHandleEvent:payload:)] && event) {
      shouldHandle = [self.automationsDelegate shouldHandleEvent:event payload:userInfo];
    }
    
    if (!shouldHandle) {
      return;
    }
    
    [self showAutomationIfExists];
  });
}

- (void)showAutomationIfExists {
  __block __weak QONAutomationsFlowCoordinator *weakSelf = self;
  [self.automationsService obtainAutomationScreensWithCompletion:^(NSArray<QONUserActionPoint *> *actionPoints, NSError * _Nullable error) {
    NSArray<QONUserActionPoint *> *sortedActions = [actionPoints sortedArrayUsingSelector:@selector(createDate)];
    QONUserActionPoint *latestAction = sortedActions.lastObject;
    NSString *automationID = latestAction.screenId;
    
    if (automationID.length > 0) {
      [weakSelf showAutomationWithID:automationID completion:nil];
    }
  }];
}

- (void)sendPushToken:(NSData *)pushTokenData {
  NSString *tokenString = [QNUtils convertHexData:pushTokenData];
  NSString *oldToken = [QNDevice current].pushNotificationsToken;
  if ([tokenString isEqualToString:oldToken] || tokenString.length == 0) {
    return;
  }
  
  [[QNDevice current] setPushNotificationsToken:tokenString];
  [[QNDevice current] setPushTokenProcessed:NO];
  
  if (!self.isSDKLaunched) {
    return;
  }
  
  [self processPushTokenRequest];
}

- (void)processPushTokenRequest {
  NSString *pushToken = [[QNDevice current] pushNotificationsToken];
  BOOL isPushTokenProcessed = [[QNDevice current] isPushTokenProcessed];
  if (!pushToken || isPushTokenProcessed) {
    return;
  }
  
  [self.notificationsService sendPushToken];
}

- (void)showAutomationWithID:(NSString *)automationID completion:(nullable QONShowScreenCompletionHandler)completion {
  __block __weak QONAutomationsFlowCoordinator *weakSelf = self;
  [self.automationsService automationWithID:automationID completion:^(QONAutomationsScreen *screen, NSError * _Nullable error) {
    if (screen) {
      [weakSelf.automationsService trackScreenShownWithID:automationID];
      QONAutomationsViewController *viewController = [weakSelf.assembly configureAutomationsViewControllerWithScreen:screen delegate:self];
      
      UIViewController *presentationViewController;
      
      if ([weakSelf.automationsDelegate respondsToSelector:@selector(controllerForNavigation)]) {
        presentationViewController = [weakSelf.automationsDelegate controllerForNavigation];
      } else {
        presentationViewController = [weakSelf topLevelViewController];
      }
      
      QONScreenPresentationConfiguration *configuration = [QONScreenPresentationConfiguration defaultConfiguration];
      if ([weakSelf.screenCustomizationDelegate respondsToSelector:@selector(presentationConfigurationForScreen:)]) {
        configuration = [weakSelf.screenCustomizationDelegate presentationConfigurationForScreen:screen.screenID];
      }

      if (configuration.presentationStyle == QONScreenPresentationStylePush) {
        [presentationViewController.navigationController pushViewController:viewController animated:configuration.animated];
      } else {
        QONAutomationsNavigationController *navigationController = [[QONAutomationsNavigationController alloc] initWithRootViewController:viewController];
        navigationController.navigationBarHidden = YES;
        UIModalPresentationStyle style = configuration.presentationStyle == QONScreenPresentationStylePopover ? UIModalPresentationPopover : UIModalPresentationFullScreen;
        navigationController.modalPresentationStyle = style;
        [presentationViewController presentViewController:navigationController animated:configuration.animated completion:nil];
      }
      
      run_block_on_main(completion, true, nil);
    } else if (error) {
      run_block_on_main(completion, false, error);
    }
  }];
}

#pragma mark - QONAutomationsViewControllerDelegate

- (void)automationsDidShowScreen:(NSString *)screenID {
  if ([self.automationsDelegate respondsToSelector:@selector(automationsDidShowScreen:)]) {
    [self.automationsDelegate automationsDidShowScreen:screenID];
  }
}

- (void)automationsDidStartExecutingActionResult:(QONActionResult *)actionResult {
  if ([self.automationsDelegate respondsToSelector:@selector(automationsDidStartExecutingActionResult:)]) {
    [self.automationsDelegate automationsDidStartExecutingActionResult:actionResult];
  }
}

- (void)automationsDidFailExecutingActionResult:(QONActionResult *)actionResult {
  if ([self.automationsDelegate respondsToSelector:@selector(automationsDidFailExecutingActionResult:)]) {
    [self.automationsDelegate automationsDidFailExecutingActionResult:actionResult];
  }
}

- (void)automationsDidFinishExecutingActionResult:(QONActionResult *)actionResult {
  if ([self.automationsDelegate respondsToSelector:@selector(automationsDidFinishExecutingActionResult:)]) {
    [self.automationsDelegate automationsDidFinishExecutingActionResult:actionResult];
  }
}

- (void)automationsFinished {
  if ([self.automationsDelegate respondsToSelector:@selector(automationsFinished)]) {
    [self.automationsDelegate automationsFinished];
  }
}

#pragma mark - Private

- (UIViewController *)topLevelViewController NS_EXTENSION_UNAVAILABLE("Automations is unavailable for extensions") {
  UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;

  while (topController.presentedViewController) {
    topController = topController.presentedViewController;
  }

  return topController;
}

@end

#endif
