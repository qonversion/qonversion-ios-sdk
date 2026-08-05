//
//  QNIdentityManager.m
//  Qonversion
//
//  Created by Surik Sarkisyan on 22.03.2021.
//  Copyright © 2021 Qonversion Inc. All rights reserved.
//

#import "QNIdentityManager.h"
#import "QNIdentityServiceInterface.h"
#import "QNUserInfoServiceInterface.h"

@implementation QNIdentityManager

- (void)identify:(NSString *)userID completion:(QNIdentityCompletionHandler)completion {
  NSString *anonUserID = [self.userInfoService obtainUserID];
  [self.identityService identify:userID anonUserID:anonUserID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    // The Product Center owns identity-attempt serialization and cancellation.
    // Persisting here would let a response that arrives after logout silently
    // restore the canceled user before the owner can reject the callback.
    completion(result, error);
  }];
}

- (BOOL)logoutIfNeeded {
  return [self.userInfoService logoutIfNeeded];
}

@end
