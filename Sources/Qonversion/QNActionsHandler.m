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

static NSString *const kQonversionScheme = @"qonversion";
static NSString *const kActionHost = @"action";

static NSString *const kLinkAction = @"link";
static NSString *const kDeeplinkAction = @"deeplink";
static NSString *const kPurchaseAction = @"purchase";
static NSString *const kRestoreAction = @"restore";
static NSString *const kNavigationAction = @"navigateTo";
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
  
  return [components.scheme isEqualToString:kQonversionScheme] && [components.host isEqualToString:kActionHost];
}

- (QNAction *)prepareDataForAction:(WKNavigationAction *)action {
  NSURLComponents *components = [NSURLComponents componentsWithString:action.request.URL.absoluteString];
  QNActionType type = QNActionTypeUnknown;
  NSDictionary *value = @{};
  
  for (NSURLQueryItem *item in [components queryItems]) {
      if ([item.name isEqualToString:@"type"]) {
        type = self.actionsTypesDictionary[item.value].integerValue ?: type;
      } else if ([item.name isEqualToString:@"data"]) {
          NSData *data = [item.value dataUsingEncoding:NSUTF8StringEncoding];
          value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      }
  }
  
  QNAction *formattedAction = [QNAction new];
  formattedAction.type = type;
  formattedAction.value = value;
  
  return formattedAction;
}

@end
