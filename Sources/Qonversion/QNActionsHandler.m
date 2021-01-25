//
//  QNActionsHandler.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNActionsHandler.h"
#import "QONAction.h"
#import <WebKit/WebKit.h>

static NSString *const kQonversionSchemeRegEx = @"^(qon-)\\w";
static NSString *const kAutomationsHost = @"automation";
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
      kLinkAction: @(QONActionTypeLink),
      kDeeplinkAction: @(QONActionTypeDeeplink),
      kCloseAction: @(QONActionTypeClose),
      kPurchaseAction: @(QONActionTypePurchase),
      kRestoreAction: @(QONActionTypeRestorePurchases),
      kNavigationAction: @(QONActionTypeNavigation),
    };
  }
  
  return self;
}

- (BOOL)isActionShouldBeHandled:(WKNavigationAction *)action {
  NSURLComponents *components = [NSURLComponents componentsWithString:action.request.URL.absoluteString];
  NSRange range = [components.scheme rangeOfString:kQonversionSchemeRegEx options:NSRegularExpressionSearch];
  
  return range.location != NSNotFound && [components.host isEqualToString:kAutomationsHost];
}

- (QONAction *)prepareDataForAction:(WKNavigationAction *)action {
  NSURLComponents *components = [NSURLComponents componentsWithString:action.request.URL.absoluteString];
  QONActionType type = QONActionTypeUnknown;
  NSMutableDictionary *value = [NSMutableDictionary new];
  
  for (NSURLQueryItem *item in [components queryItems]) {
      if ([item.name isEqualToString:@"action"]) {
        type = self.actionsTypesDictionary[item.value].integerValue ?: type;
      } else if ([item.name isEqualToString:@"data"]) {
        value[@"value"] = item.value;
      }
  }
  
  QONAction *formattedAction = [QONAction new];
  formattedAction.type = type;
  formattedAction.value = [value copy];
  
  return formattedAction;
}

@end
