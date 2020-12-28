//
//  QNActionsService.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNAutomationsService.h"
#import "QNAutomationScreen.h"
#import "QNAPIClient.h"
#import "QNAutomationsMapper.h"
#import "QNUtils.h"
#import "QNUserActionPoint.h"

@implementation QNAutomationsService

- (void)automationWithID:(NSString *)automationID completion:(QNAutomationsCompletionHandler)completion {
  __block __weak QNAutomationsService *weakSelf = self;
  [self.apiClient automationWithID:automationID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QNAutomationScreen *screen = [weakSelf.mapper mapScreen:dict];
    NSError *mappedError = [weakSelf.mapper mapError:dict];
    NSError *screenError = mappedError ?: error ;
    
    
  }];
}

- (void)obtainAutomationScreensWithCompletion:(QNActiveAutomationCompletionHandler)completion {
  __block __weak QNAutomationsService *weakSelf = self;
  [self.apiClient userActionPointsWithCompletion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    NSArray<QNUserActionPoint *> *actions = [weakSelf.mapper mapUserActionPoints:dict];

    run_block_on_main(completion, actions, nil);
  }];
}

- (void)trackScreenShownWithID:(NSString *)automationID {
  [self.apiClient trackScreenShownWithID:automationID];
}

@end
