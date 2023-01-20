//
//  QONAutomationsViewController.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS

#import "QONAutomationsViewController.h"
#import "QONAutomationsService.h"
#import "QONAutomationsFlowAssembly.h"
#import "QONAutomationsActionsHandler.h"
#import "QONActionResult.h"
#import "QONAutomationsScreen.h"
#import "QONAutomationsConstants.h"
#import "QONAutomationsScreenProcessor.h"

#import "Qonversion.h"

#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>

@interface QONAutomationsViewController () <WKNavigationDelegate, UIScrollViewDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

@end

@implementation QONAutomationsViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  
  self.webView = [WKWebView new];
  self.webView.navigationDelegate = self;
  [self.view addSubview:self.webView];
  
  self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
  self.activityIndicator.color = [UIColor lightGrayColor];
  self.activityIndicator.hidesWhenStopped = YES;
  [self.view addSubview:self.activityIndicator];
  
  self.webView.scrollView.showsVerticalScrollIndicator = NO;
  
  self.webView.scrollView.delegate = self;
  
  [self.delegate automationsDidShowScreen:self.screen.screenID];
  
  __block __weak QONAutomationsViewController *weakSelf = self;
  
  [self.screenProcessor processScreen:self.screen.htmlString completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    if (error) {
      [weakSelf showErrorAlertWithTitle:kAutomationsErrorAlertTitle message:error.localizedDescription handler:^(UIAlertAction *action) {
        if (weakSelf.navigationController.viewControllers.count > 1) {
          [weakSelf.navigationController popViewControllerAnimated:YES];
        } else {
          [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }
      }];
      
      return;
    }
    
    [weakSelf.webView loadHTMLString:result baseURL:nil];
  }];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  
  self.activityIndicator.center = self.view.center;
  self.webView.frame = self.view.frame;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  
  BOOL isActionShouldBeHandeled = [self.actionsHandler isActionShouldBeHandled:navigationAction];
  if (!isActionShouldBeHandeled) {
    decisionHandler(WKNavigationActionPolicyAllow);
    return;
  }
  
  decisionHandler(WKNavigationActionPolicyCancel);
  
  [self handleAction:navigationAction];
}

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message handler:(void (^ __nullable)(UIAlertAction *action))handler {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
  
  UIAlertAction *action = [UIAlertAction actionWithTitle:kAutomationsErrorOkActionTitle style:UIAlertActionStyleCancel handler:handler];
  [alert addAction:action];
  
  [self.navigationController presentViewController:alert animated:YES completion:nil];
}

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
  [self showErrorAlertWithTitle:title message:message handler:nil];
}

#pragma mark Actions

- (void)handleAction:(WKNavigationAction *)navigationAction {
  QONActionResult *action = [self.actionsHandler prepareDataForAction:navigationAction];
  [self.delegate automationsDidStartExecutingActionResult:action];
  
  switch (action.type) {
    case QONActionResultTypeURL: {
      [self handleLinkAction:action];
      break;
    }
    case QONActionResultTypeDeeplink: {
      [self handleDeepLinkAction:action];
      break;
    }
    case QONActionResultTypeClose:
      [self handleCloseAction:action];
      break;
    case QONActionResultTypeCloseAll:
      [self handleCloseAllAction:action];
      break;
    case QONActionResultTypePurchase: {
      [self handlePurchaseAction:action];
      break;
    }
    case QONActionResultTypeRestore: {
      [self handleRestoreAction:action];
      break;
    }
    case QONActionResultTypeNavigation: {
      [self handleNavigationAction:action];
      break;
    }
    default:
      break;
  }
}

- (void)handleLinkAction:(QONActionResult *)action {
  NSString *urlString = action.parameters[kAutomationsValueKey];
  if (urlString.length > 0) {
    NSURL *url = [NSURL URLWithString:urlString];
    SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:url];
    [self.navigationController presentViewController:safariViewController animated:true completion:nil];
    [self.delegate automationsDidFinishExecutingActionResult:action];
  } else {
    [self.delegate automationsDidFailExecutingActionResult:action];
  }
}

- (void)handleCloseAction:(QONActionResult *)action {
  if (self.navigationController.viewControllers.count > 1) {
    [self.navigationController popViewControllerAnimated:YES];
  } else {
    [self finishAndCloseAutomationsWithActionResult:action];
  }
}

- (void)handleCloseAllAction:(QONActionResult *)action {
  [self finishAndCloseAutomationsWithActionResult:action];
}

- (void)handleDeepLinkAction:(QONActionResult *)action NS_EXTENSION_UNAVAILABLE("Automations is unavailable for extensions") {
  NSString *deeplinkString = action.parameters[kAutomationsValueKey];
  if (deeplinkString.length > 0) {
    NSURL *url = [NSURL URLWithString:deeplinkString];
    BOOL canOpen = [[UIApplication sharedApplication] canOpenURL:url];
    if (canOpen) {
      [self finishAndCloseAutomationsWithActionResult:action];
      [[UIApplication sharedApplication] openURL:url];
    } else {
      [self.delegate automationsDidFailExecutingActionResult:action];
      [self closeAutomationsWithActionResult:action];
    }
  } else {
    [self.delegate automationsDidFailExecutingActionResult:action];
  }
}

- (void)handlePurchaseAction:(QONActionResult *)action {
  NSString *productID = action.parameters[kAutomationsValueKey];
  if (productID.length > 0) {
    [self.activityIndicator startAnimating];
    __block __weak QONAutomationsViewController *weakSelf = self;
    [[Qonversion sharedInstance] purchase:productID completion:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error, BOOL cancelled) {
      [weakSelf.activityIndicator stopAnimating];
      
      action.error = error;
      
      if (cancelled) {
        [weakSelf.delegate automationsDidFailExecutingActionResult:action];
        return;
      }
      
      if (error) {
        [weakSelf.delegate automationsDidFailExecutingActionResult:action];
        [weakSelf showErrorAlertWithTitle:kAutomationsErrorAlertTitle message:error.localizedDescription];
        return;
      }
      
      [weakSelf finishAndCloseAutomationsWithActionResult:action];
    }];
  }
}

- (void)handleRestoreAction:(QONActionResult *)action {
  __block __weak QONAutomationsViewController *weakSelf = self;
  [self.activityIndicator startAnimating];
  [[Qonversion sharedInstance] restore:^(NSDictionary<NSString *,QONEntitlement *> * _Nonnull result, NSError * _Nullable error) {
    [weakSelf.activityIndicator stopAnimating];
    
    action.error = error;
    
    if (error) {
      [weakSelf.delegate automationsDidFailExecutingActionResult:action];
      [weakSelf showErrorAlertWithTitle:kAutomationsErrorAlertTitle message:error.localizedDescription];
      return;
    }
    
    [weakSelf finishAndCloseAutomationsWithActionResult:action];
  }];
}

- (void)handleNavigationAction:(QONActionResult *)action {
  NSString *automationID = action.parameters[kAutomationsValueKey];
  __block __weak QONAutomationsViewController *weakSelf = self;
  [self.activityIndicator startAnimating];
  [self.automationsService automationWithID:automationID completion:^(QONAutomationsScreen *screen, NSError * _Nullable error) {
    [weakSelf.activityIndicator stopAnimating];
    if (screen.htmlString) {
      QONAutomationsViewController *viewController = [weakSelf.flowAssembly configureAutomationsViewControllerWithScreen:screen delegate:weakSelf.delegate];
      [weakSelf.automationsService trackScreenShownWithID:automationID];
      [weakSelf.navigationController pushViewController:viewController animated:YES];
      [weakSelf.delegate automationsDidFinishExecutingActionResult:action];
    } else if (error) {
      [weakSelf showErrorAlertWithTitle:kAutomationsShowScreenErrorAlertTitle message:error.localizedDescription];
      [weakSelf.delegate automationsDidFailExecutingActionResult:action];
    } else {
      [weakSelf.delegate automationsDidFailExecutingActionResult:action];
    }
  }];
}

- (void)finishAndCloseAutomationsWithActionResult:(QONActionResult *)actionResult {
  [self.delegate automationsDidFinishExecutingActionResult:actionResult];
  
  [self closeAutomationsWithActionResult:actionResult];
}

- (void)closeAutomationsWithActionResult:(QONActionResult *)actionResult {
  if (self.navigationController.presentingViewController) {
    [self dismissViewControllerAnimated:YES completion:^{
      [self.delegate automationsFinished];
    }];
  } else {
    UIViewController *vcToPop = [self firstNonQonversionViewController];
    
    [self.navigationController popToViewController:vcToPop animated:YES];
  }
}

- (UIViewController *)firstNonQonversionViewController {
  NSArray *currentViewControllers = [self.navigationController.viewControllers copy];
  UIViewController *firstNonQonversionVC = [currentViewControllers firstObject];
  for (NSUInteger i = currentViewControllers.count - 1; i > 0; i--) {
    UIViewController *controller = currentViewControllers[i];
    if (![controller isKindOfClass:[QONAutomationsViewController class]]) {
      firstNonQonversionVC = controller;
      break;
    }
  }
  
  return firstNonQonversionVC;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
  scrollView.pinchGestureRecognizer.enabled = NO;
}

@end

#endif
