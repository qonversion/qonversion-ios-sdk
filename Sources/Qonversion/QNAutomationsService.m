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
#import "QNScreensMapper.h"
#import "QNUtils.h"

@implementation QNAutomationsService

- (void)automationWithID:(NSString *)automationID completion:(QNAutomationsCompletionHandler)completion {
  __block __weak QNAutomationsService *weakSelf = self;
  [self.apiClient automationWithID:automationID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    QNAutomationScreen *screen = [weakSelf.mapper mapScreen:dict];
    NSError *mappedError = [weakSelf.mapper mapError:dict];
    NSError *screenError = mappedError ?: error ;
    
    run_block_on_main(completion, screen, screenError);
  }];
}

- (void)obtainAutomationScreensWithCompletion:(QNActiveAutomationsCompletionHandler)completion {
  
}

- (void)trackScreenShownWithID:(NSString *)automationID {
  [self.apiClient trackScreenShownWithID:automationID];
}

@end
