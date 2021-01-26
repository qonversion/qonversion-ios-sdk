//
//  QONActionsHandler.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsActionsHandler.h"
#import "QONActionResult.h"
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

@interface QONAutomationsActionsHandler()

@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *actionsTypesDictionary;

@end

@implementation QONAutomationsActionsHandler

- (instancetype)init {
  self = [super init];
  
  if (self) {
    _actionsTypesDictionary = @{
      kLinkAction: @(QONActionTypeURL),
      kDeeplinkAction: @(QONActionTypeDeeplink),
      kCloseAction: @(QONActionTypeClose),
      kPurchaseAction: @(QONActionTypePurchase),
      kRestoreAction: @(QONActionTypeRestore),
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

- (QONActionResult *)prepareDataForAction:(WKNavigationAction *)action {
  NSURLComponents *components = [NSURLComponents componentsWithString:action.request.URL.absoluteString];
  QONActionResultType type = QONActionTypeUnknown;
  NSMutableDictionary *value = [NSMutableDictionary new];
  
  for (NSURLQueryItem *item in [components queryItems]) {
      if ([item.name isEqualToString:@"action"]) {
        type = self.actionsTypesDictionary[item.value].integerValue ?: type;
      } else if ([item.name isEqualToString:@"data"]) {
        value[@"value"] = item.value;
      }
  }
  
  QONActionResult *formattedAction = [QONActionResult new];
  formattedAction.type = type;
  formattedAction.value = [value copy];
  
  return formattedAction;
}

@end
