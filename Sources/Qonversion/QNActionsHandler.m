//
//  QNActionsHandler.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNActionsHandler.h"
#import "QNAction.h"
#import <WebKit/WebKit.h>

static NSString *const kQonversionSchemeRegEx = @"^(q-)\\w";
static NSString *const kAutomationsHost = @"automations";
static NSString *const kActionHost = @"action";

static NSString *const kLinkAction = @"url";
static NSString *const kDeeplinkAction = @"deeplink";
static NSString *const kPurchaseAction = @"purchase";
static NSString *const kRestoreAction = @"restore";
static NSString *const kNavigationAction = @"navigate";
static NSString *const kCloseAction = @"close";

@interface QNActionsHandler()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *actionsTypesDictionary;

@end

@implementation QNActionsHandler

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _actionsTypesDictionary = @{
      kLinkAction: @(QNActionTypeLink),
      kDeeplinkAction: @(QNActionTypeDeeplink),
      kCloseAction: @(QNActionTypeClose),
      kPurchaseAction: @(QNActionTypePurchase),
      kRestoreAction: @(QNActionTypeRestorePurchases),
      kNavigationAction: @(QNActionTypeNaivgation),
    };
  }
  
  return self;
}

- (BOOL)isActionShouldBeHandled:(WKNavigationAction *)action {
  NSURLComponents *components = [NSURLComponents componentsWithString:action.request.URL.absoluteString];
  NSRange range = [components.scheme rangeOfString:kQonversionSchemeRegEx options:NSRegularExpressionSearch];
  
  return range.location != NSNotFound && [components.host isEqualToString:kAutomationsHost];
}

- (QNAction *)prepareDataForAction:(WKNavigationAction *)action {
  NSURLComponents *components = [NSURLComponents componentsWithString:action.request.URL.absoluteString];
  QNActionType type = QNActionTypeUnknown;
  NSMutableDictionary *value = [NSMutableDictionary new];
  
  for (NSURLQueryItem *item in [components queryItems]) {
      if ([item.name isEqualToString:@"action"]) {
        type = self.actionsTypesDictionary[item.value].integerValue ?: type;
      } else if ([item.name isEqualToString:@"data"]) {
        value[@"value"] = item.value;
      }
  }
  
  QNAction *formattedAction = [QNAction new];
  formattedAction.type = type;
  formattedAction.value = [value copy];
  
  return formattedAction;
}

@end
