//
//  QONAutomationsService.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QONAutomationsService.h"
#import "QONAutomationsScreen.h"
#import "QNAPIClient.h"
#import "QONAutomationsMapper.h"
#import "QNUtils.h"
#import "QONUserActionPoint.h"

@implementation QONAutomationsService

- (void)automationWithID:(NSString *)automationID completion:(QONAutomationsCompletionHandler)completion {
  __block __weak QONAutomationsService *weakSelf = self;
  [self.apiClient automationWithID:automationID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QONAutomationsScreen *screen = [weakSelf.mapper mapScreen:dict];

    run_block_on_main(completion, screen, error);
  }];
}

- (void)obtainAutomationScreensWithCompletion:(QONActiveAutomationCompletionHandler)completion {
  __block __weak QONAutomationsService *weakSelf = self;
  [self.apiClient userActionPointsWithCompletion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    NSArray<QONUserActionPoint *> *actions = [weakSelf.mapper mapUserActionPoints:dict];

    run_block_on_main(completion, actions, nil);
  }];
}

- (void)trackScreenShownWithID:(NSString *)automationID {
  [self.apiClient trackScreenShownWithID:automationID];
}

@end
