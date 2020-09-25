//
//  QNActionsService.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 23.09.2020.
//  Copyright © 2020 Qonversion Inc. All rights reserved.
//

#import "QNActionsService.h"

@implementation QNActionsService

- (void)actionWithID:(NSString *)actionID completion:(QNActionsCompletionHandler)completion {
  [self.apiClient actionWithID:actionID completion:^(NSDictionary * _Nullable dict, NSError * _Nullable error) {
    NSLog(@"LALA");
  }];
}

@end
