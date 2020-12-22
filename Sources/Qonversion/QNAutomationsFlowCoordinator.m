//
//  QNAutomationsFlowCoordinator.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 24.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNAutomationsFlowCoordinator.h"
#import "QNAutomationsFlowAssembly.h"
#import "QNAutomationsDelegate.h"
#import "QNAutomationsViewController.h"

@interface QNAutomationsFlowCoordinator() <QNAutomationsViewControllerDelegate>

@property (nonatomic, weak) id<QNAutomationsDelegate> automationsDelegate;
@property (nonatomic, strong) QNAutomationsFlowAssembly *assembly;

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
  }
  
  return self;
}

- (void)setAutomationsDelegate:(id<QNAutomationsDelegate>)automationsDelegate {
  _automationsDelegate = automationsDelegate;
}

- (void)showAutomationWithID:(NSString *)automationID {
  BOOL canShowAutomation = YES;
  
  if ([self.automationsDelegate respondsToSelector:@selector(canShowAutomationWithID:)]) {
    canShowAutomation = [self.automationsDelegate canShowAutomationWithID:automationID];
  }
  
  if (!canShowAutomation) {
    return;
  }
  
  QNAutomationsViewController *viewController = [self.assembly configureAutomationsViewControllerWithID:automationID delegate:self];
  
  UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
  navigationController.navigationBarHidden = YES;
  
  UIViewController *presentationViewController;
  
  if ([self.automationsDelegate respondsToSelector:@selector(controllerForNavigation)]) {
    presentationViewController = [self.automationsDelegate controllerForNavigation];
  } else {
    presentationViewController = [self topLevelViewController];
  }
  
  [presentationViewController presentViewController:navigationController animated:YES completion:nil];
}

- (void)automationsViewController:(QNAutomationsViewController *)viewController didFinishAutomation:(QNAutomation *)automation {
  if ([self.automationsDelegate respondsToSelector:@selector(automationFlowFinished)]) {
    [self.automationsDelegate automationFlowFinished];
  }
}

#pragma mark - Priate

- (UIViewController *)topLevelViewController {
  return nil;
}

@end
