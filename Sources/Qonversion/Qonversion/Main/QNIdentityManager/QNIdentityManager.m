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

NSInteger const kUserNotFoundErrorCode = 404;

@implementation QNIdentityManager

- (void)identify:(NSString *)userID completion:(QNIdentityCompletionHandler)completion {
  __block __weak QNIdentityManager *weakSelf = self;
  
  NSString *anonUserID = [self.userInfoService obtainUserID];
  
  [weakSelf.identityService obtainIdentity:userID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
    if (error.code == kUserNotFoundErrorCode) {
      [weakSelf.identityService createIdentity:userID anonUserID:anonUserID completion:^(NSString * _Nullable result, NSError * _Nullable error) {
        [weakSelf handleIdentityResult:userID identityResultID:result error:error completion:completion];
      }];
      return;
    }
    
    [weakSelf handleIdentityResult:userID identityResultID:result error:error completion:completion];
  }];
}

- (void)handleIdentityResult:(NSString *)userID identityResultID:(NSString *)resultID error:(NSError *)error completion:(QNIdentityCompletionHandler)completion {
  if (!error) {
    [self.userInfoService storeCustomUserID:userID];
  }
  
  if (resultID.length > 0) {
    [self.userInfoService storeIdentity:resultID];
  }
  
  completion(resultID, error);
}

- (BOOL)logoutIfNeeded {
  return [self.userInfoService logoutIfNeeded];
}

@end
