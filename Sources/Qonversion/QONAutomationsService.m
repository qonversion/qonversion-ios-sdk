//
//  QONActionsService.m
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
#import "QNUserActionPoint.h"

@implementation QONAutomationsService

- (void)automationWithID:(NSString *)automationID completion:(QNAutomationsCompletionHandler)completion {
  __block __weak QONAutomationsService *weakSelf = self;
  [self.apiClient automationWithID:automationID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QONAutomationsScreen *screen = [weakSelf.mapper mapScreen:dict];
    NSError *mappedError = [weakSelf.mapper mapError:dict];
    NSError *screenError = mappedError ?: error ;
    
    run_block_on_main(completion, screen, screenError);
  }];
}

- (void)obtainAutomationScreensWithCompletion:(QNActiveAutomationCompletionHandler)completion {
  __block __weak QONAutomationsService *weakSelf = self;
  [self.apiClient userActionPointsWithCompletion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    NSArray<QNUserActionPoint *> *actions = [weakSelf.mapper mapUserActionPoints:dict];

    run_block_on_main(completion, actions, nil);
  }];
}

- (void)trackScreenShownWithID:(NSString *)automationID {
  [self.apiClient trackScreenShownWithID:automationID];
}

@end
