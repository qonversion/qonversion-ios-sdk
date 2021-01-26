//
//  QONAutomationsViewController.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsViewController.h"
#import "QONAutomationsService.h"
#import "QONAutomationsFlowAssembly.h"
#import "QONAutomationsActionsHandler.h"
#import "QONActionResult.h"
#import "QONAutomationsScreen.h"
#import "QONAutomationsConstants.h"

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
  
  [self.webView loadHTMLString:self.htmlString baseURL:nil];
  self.webView.scrollView.delegate = self;
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

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
  
  UIAlertAction *action = [UIAlertAction actionWithTitle:kAutomationsErrorOkActionTitle style:UIAlertActionStyleCancel handler:nil];
  [alert addAction:action];
  
  [self.navigationController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Private

#pragma mark Actions

- (void)handleAction:(WKNavigationAction *)navigationAction {
  QONActionResult *action = [self.actionsHandler prepareDataForAction:navigationAction];
  
  switch (action.type) {
    case QONActionTypeLink: {
      [self handleLinkAction:action];
      break;
    }
    case QONActionTypeDeeplink: {
      [self handleDeepLinkAction:action];
      break;
    }
    case QONActionTypeClose:
      [self handleCloseAction:action];
      break;
    case QONActionTypePurchase: {
      [self handlePurchaseAction:action];
      break;
    }
    case QONActionTypeRestorePurchases: {
      [self handleRestoreAction:action];
      break;
    }
    case QONActionTypeNavigation: {
      [self handleNavigationAction:action];
      break;
    }
    default:
      break;
  }
}

- (void)handleLinkAction:(QONActionResult *)action {
  NSString *urlString = action.value[kAutomationsValueKey];
  if (urlString.length > 0) {
    NSURL *url = [NSURL URLWithString:urlString];
    SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:url];
    [self.navigationController presentViewController:safariViewController animated:true completion:nil];
  }
}

- (void)handleCloseAction:(QONActionResult *)action {
  __block __weak QONAutomationsViewController *weakSelf = self;
  [self dismissViewControllerAnimated:YES completion:^{
    [weakSelf.delegate automationsViewController:weakSelf didFinishAction:action];
  }];
}

- (void)handleDeepLinkAction:(QONActionResult *)action {
  NSString *deeplinkString = action.value[kAutomationsValueKey];
  if (deeplinkString.length > 0) {
    __block __weak QONAutomationsViewController *weakSelf = self;
    NSURL *url = [NSURL URLWithString:deeplinkString];
    [self dismissViewControllerAnimated:YES completion:^{
      [weakSelf.delegate automationsViewController:weakSelf didFinishAction:action];
      [[UIApplication sharedApplication] openURL:url];
    }];
  }
}

- (void)handlePurchaseAction:(QONActionResult *)action {
  NSString *productID = action.value[kAutomationsValueKey];
  if (productID.length > 0) {
    [self.activityIndicator startAnimating];
    __block __weak QONAutomationsViewController *weakSelf = self;
    [Qonversion purchase:productID completion:^(NSDictionary<NSString *,QNPermission *> * _Nonnull result, NSError * _Nullable error, BOOL cancelled) {
      [weakSelf.activityIndicator stopAnimating];
      
      if (cancelled) {
        return;
      }
      
      if (error) {
        [weakSelf showErrorAlertWithTitle:kAutomationsErrorAlertTitle message:error.localizedDescription];
        return;
      }
      
      [weakSelf dismissViewControllerAnimated:YES completion:^{
        [weakSelf.delegate automationsViewController:weakSelf didFinishAction:action];
      }];
    }];
  }
}

- (void)handleRestoreAction:(QONActionResult *)action {
  __block __weak QONAutomationsViewController *weakSelf = self;
  [self.activityIndicator startAnimating];
  [Qonversion restoreWithCompletion:^(NSDictionary<NSString *,QNPermission *> * _Nonnull result, NSError * _Nullable error) {
    [weakSelf.activityIndicator stopAnimating];
    if (error) {
      [weakSelf showErrorAlertWithTitle:kAutomationsErrorAlertTitle message:error.localizedDescription];
      return;
    }
    
    [weakSelf dismissViewControllerAnimated:YES completion:^{
      [weakSelf.delegate automationsViewController:weakSelf didFinishAction:action];
    }];
  }];
}

- (void)handleNavigationAction:(QONActionResult *)action {
  NSString *automationID = action.value[kAutomationsValueKey];
  __block __weak QONAutomationsViewController *weakSelf = self;
  [self.activityIndicator startAnimating];
  [self.automationsService automationWithID:automationID completion:^(QONAutomationsScreen *screen, NSError * _Nullable error) {
    [weakSelf.activityIndicator stopAnimating];
    if (screen.htmlString) {
      QONAutomationsViewController *viewController = [weakSelf.flowAssembly configureAutomationsViewControllerWithHtmlString:screen.htmlString delegate:weakSelf.delegate];
      [weakSelf.automationsService trackScreenShownWithID:automationID];
      [weakSelf.navigationController pushViewController:viewController animated:YES];
    } else if (error) {
      [weakSelf showErrorAlertWithTitle:kAutomationsShowScreenErrorAlertTitle message:error.localizedDescription];
    }
  }];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
  scrollView.pinchGestureRecognizer.enabled = NO;
}

@end
